import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { buildSyntheticEmail } from './lib/loginIdentifier';
import { nextMemberNumber } from './lib/memberNumber';
import { parseOptionalDate } from './lib/parseDate';
import { generateTemporaryPassword } from './lib/tempPassword';

const inputSchema = z.object({
  name: z.string().min(1),
  // Pedido pelo Carlo depois de testar "Criar utilizador": dados de
  // contacto/pessoais, todos opcionais — o Gestor pode não os ter à
  // mão no momento da criação, e continua a poder preenchê-los depois
  // (`MemberDetailScreen`, updateMemberProfile).
  phone: z.string().optional(),
  email: z.string().optional(),
  birthDate: z.string().optional(),
  address: z.string().optional(),
  nif: z.string().optional(),
  emergencyContact: z.string().optional(),
});

/**
 * UC22 — Gestor cria a conta de um membro. Gera o número de sócio
 * automaticamente (decisão fechada), cria a conta no Firebase Auth com
 * um email sintético (ver lib/loginIdentifier.ts) e uma password
 * temporária, marca `passwordTemporaria: true`, e atribui os custom
 * claims (tenantId, roles: ['member']) — Platform Foundation §14.
 *
 * Só um Gestor do próprio tenant pode chamar isto (requireManager).
 */
export const createMember = onCall(async (request) => {
  const caller = requireManager(request);
  // cada chamada cria uma conta no Firebase Auth; 20 em 5 minutos
  // cobre a inscrição de uma turma inteira e trava a criação em
  // massa
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'createMember',
    maxCalls: 20,
    windowSeconds: 300,
  });

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  // `email` aqui é o CONTACTO (`MemberSummary.email`), distinto do
  // email sintético de login gerado abaixo — nomes diferentes de
  // propósito, para nunca confundir os dois no resto da função.
  const { name, phone, email: contactEmail, birthDate, address, nif, emergencyContact } =
    parsed.data;

  const firestore = getFirestore();
  const auth = getAuth();

  // Validado ANTES de criar seja o que for: uma data malformada não
  // pode chegar ao ponto de já existir uma conta no Auth para desfazer.
  const birthTimestamp = parseOptionalDate(birthDate, 'birthDate');

  const memberNumber = await nextMemberNumber(firestore, caller.tenantId);
  const loginEmail = buildSyntheticEmail(caller.tenantId, memberNumber);
  const temporaryPassword = generateTemporaryPassword();

  const userRecord = await auth.createUser({
    email: loginEmail,
    password: temporaryPassword,
    displayName: name,
  });

  // Fase 8 (revisão geral) — a partir daqui já existe uma conta no
  // Firebase Auth. Se as claims ou o documento do membro falharem,
  // ficava um utilizador ÓRFÃO: conseguia autenticar-se (a password
  // temporária foi mesmo criada) mas não tinha `members/{uid}` nem
  // `tenantId` nas claims, ou seja, entrava na app num estado que
  // nenhum ecrã sabe tratar — e o Gestor não tinha forma de o corrigir
  // pela UI, porque a lista de membros lê o Firestore, onde ele não
  // aparece. O `catch` desfaz a conta e devolve o erro real.
  try {
    await auth.setCustomUserClaims(userRecord.uid, {
      tenantId: caller.tenantId,
      roles: ['member'],
    });

    await firestore
      .collection('tenants')
      .doc(caller.tenantId)
      .collection('members')
      .doc(userRecord.uid)
      .set({
        userId: userRecord.uid,
        memberNumber,
        name,
        status: 'active',
        passwordTemporaria: true,
        phone: phone ?? '',
        email: contactEmail ?? '',
        birthDate: birthTimestamp,
        address: address ?? '',
        nif: nif ?? '',
        emergencyContact: emergencyContact ?? '',
        createdAt: FieldValue.serverTimestamp(),
        createdBy: caller.uid,
      });
  } catch (err) {
    await auth.deleteUser(userRecord.uid).catch(() => undefined);
    throw err;
  }

  return {
    uid: userRecord.uid,
    memberNumber,
    temporaryPassword,
  };
});
