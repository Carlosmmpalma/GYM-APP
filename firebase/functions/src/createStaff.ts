import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { generateTemporaryPassword } from './lib/tempPassword';

const inputSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  roles: z.array(z.enum(['instructor', 'manager'])).min(1),
  // Fase 6 (UC12/22 fechado) — só faz sentido para quem tem role
  // instructor; opcional porque um Gestor puro nunca preenche isto.
  modalityIds: z.array(z.string().min(1)).optional(),
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
  const { name, email, roles, modalityIds } = parsed.data;

  const firestore = getFirestore();
  const auth = getAuth();

  const temporaryPassword = generateTemporaryPassword();

  const userRecord = await auth.createUser({
    email,
    password: temporaryPassword,
    displayName: name,
  });

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
      createdAt: FieldValue.serverTimestamp(),
      createdBy: caller.uid,
    });

  return {
    uid: userRecord.uid,
    email,
    temporaryPassword,
  };
});
