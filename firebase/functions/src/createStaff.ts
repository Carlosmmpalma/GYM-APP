import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { parseOptionalDate } from './lib/parseDate';
import { generateTemporaryPassword } from './lib/tempPassword';

const inputSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  roles: z.array(z.enum(['instructor', 'manager'])).min(1),
  // Fase 6 (UC12/22 fechado) — só faz sentido para quem tem role
  // instructor; opcional porque um Gestor puro nunca preenche isto.
  modalityIds: z.array(z.string().min(1)).optional(),
  // Pedido pelo Carlo depois de testar "Criar utilizador": staff
  // ganha os mesmos dados pessoais opcionais do Aluno (menos `email`,
  // que aqui já é obrigatório — é o login).
  phone: z.string().optional(),
  birthDate: z.string().optional(),
  address: z.string().optional(),
  nif: z.string().optional(),
  emergencyContact: z.string().optional(),
});

/**
 * Cria uma conta de staff (instrutor e/ou gestor).
 *
 * Decisão fechada (confirmada pelo Carlos, Fase 3): ao contrário de
 * createMember (UC22, login por nº de sócio), staff usa o email real
 * para login — não faz parte do fluxo "nº de sócio" descrito no UC01,
 * que é especificamente sobre Alunos. `login_screen.dart` aceita as
 * duas coisas no mesmo campo (ver `firebase_auth_repository.dart`).
 *
 * Domain Model v1 §6: um instrutor pode também ser membro do ginásio —
 * isso é uma segunda chamada a createMember para a mesma pessoa (mesmo
 * uid ficaria só se reutilizássemos o mesmo email; por agora tratamos
 * como contas separadas até este caso aparecer num use case).
 */
export const createStaff = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { name, email, roles, modalityIds, phone, birthDate, address, nif, emergencyContact } =
    parsed.data;

  const firestore = getFirestore();
  const auth = getAuth();

  // Ver nota em `createMember.ts` — validar antes de criar a conta.
  const birthTimestamp = parseOptionalDate(birthDate, 'birthDate');

  const temporaryPassword = generateTemporaryPassword();

  const userRecord = await auth.createUser({
    email,
    password: temporaryPassword,
    displayName: name,
  });

  // Mesmo rollback de `createMember.ts`: um staff sem `staff/{uid}` ou
  // sem claims consegue autenticar-se e fica preso num estado que
  // nenhum ecrã trata. Aqui é ainda mais visível do que nos membros,
  // porque o email de login é real e a pessoa vai mesmo tentar entrar.
  try {
    await auth.setCustomUserClaims(userRecord.uid, {
      tenantId: caller.tenantId,
      roles,
    });

    await firestore
      .collection('tenants')
      .doc(caller.tenantId)
      .collection('staff')
      .doc(userRecord.uid)
      .set({
        userId: userRecord.uid,
        name,
        email,
        roles,
        modalityIds: modalityIds ?? [],
        status: 'active',
        passwordTemporaria: true,
        phone: phone ?? '',
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
    email,
    temporaryPassword,
  };
});
