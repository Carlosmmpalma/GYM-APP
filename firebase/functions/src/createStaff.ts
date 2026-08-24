import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseOptionalDate } from './lib/parseDate';
import { generateTemporaryPassword } from './lib/tempPassword';
import { parseInput, rethrowAuthError } from './lib/validation';

const inputSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  roles: z.array(z.enum(['instructor', 'manager'])).min(1),
  // Fase 6 (UC12/22 fechado) — só faz sentido para quem tem role
  // instructor; opcional porque um Gestor puro nunca preenche isto.
  modalityIds: z.array(z.string().min(1)).optional(),
  // Fase 11 — os serviços que o instrutor pode lecionar. Ao contrário
  // das modalidades, que descrevem, isto AUTORIZA: as Security Rules
  // só o deixam criar aulas destes serviços.
  serviceIds: z.array(z.string().min(1)).optional(),
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
  // staff é criado às unidades, nunca em lote
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'createStaff',
    maxCalls: 10,
    windowSeconds: 300,
  });

  const { name, email, roles, modalityIds, serviceIds, phone, birthDate, address, nif, emergencyContact } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const auth = getAuth();

  // Ver nota em `createMember.ts` — validar antes de criar a conta.
  const birthTimestamp = parseOptionalDate(birthDate, 'birthDate');

  const temporaryPassword = generateTemporaryPassword();

  // Falhas do Firebase Auth traduzidas antes de subirem: sem isto, um
  // email já usado devolvia `internal` / "INTERNAL" — o Gestor via
  // "erro interno" quando o que se passava era uma coisa que ele
  // percebe e resolve num segundo. Ver `lib/validation.ts`.
  let userRecord;
  try {
    userRecord = await auth.createUser({
      email,
      password: temporaryPassword,
      displayName: name,
    });
  } catch (error) {
    rethrowAuthError(error);
  }

  // Mesmo rollback de `createMember.ts`: um staff sem `staff/{uid}` ou
  // sem claims consegue autenticar-se e fica preso num estado que
  // nenhum ecrã trata. Aqui é ainda mais visível do que nos membros,
  // porque o email de login é real e a pessoa vai mesmo tentar entrar.
  try {
    await auth.setCustomUserClaims(userRecord.uid, {
      tenantId: caller.tenantId,
      roles,
    });

    const staffRef = firestore
      .collection('tenants')
      .doc(caller.tenantId)
      .collection('staff')
      .doc(userRecord.uid);

    // Os dados pessoais do staff vivem numa subcoleção PRIVADA, e não
    // no documento principal.
    //
    // O documento de `staff` é legível por todo o tenant — é dele que
    // sai o nome do instrutor no cartão de uma aula, que qualquer aluno
    // vê. Com a morada, o NIF, a data de nascimento e o contacto de
    // emergência lá dentro, isso queria dizer que qualquer aluno podia
    // ler o NIF e a morada dos instrutores. É a mesma fuga que já tinha
    // sido fechada em `members` na Fase 11 — o staff ficou para trás.
    //
    // O que fica no documento público é o mínimo para a app funcionar:
    // nome, email (é a identidade de login e o contacto profissional),
    // papéis, serviços/modalidades e estado.
    const batch = firestore.batch();
    batch.set(staffRef, {
      userId: userRecord.uid,
      name,
      email,
      roles,
      modalityIds: modalityIds ?? [],
      serviceIds: serviceIds ?? [],
      status: 'active',
      passwordTemporaria: true,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: caller.uid,
    });
    batch.set(staffRef.collection('private').doc('profile'), {
      phone: phone ?? '',
      birthDate: birthTimestamp,
      address: address ?? '',
      nif: nif ?? '',
      emergencyContact: emergencyContact ?? '',
      updatedAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
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
