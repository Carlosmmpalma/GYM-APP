import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  staffId: z.string().min(1),
  roles: z
    .array(z.enum(['manager', 'instructor']))
    .min(1, 'Um membro do staff tem de ter pelo menos um papel.'),
});

/**
 * Fase 11 — promover ou despromover staff (Instrutor ↔ Gestor).
 *
 * Os papéis eram decididos na criação e nunca mais mudavam: um
 * instrutor que passasse a sócio-gerente exigia um developer a mexer
 * nas custom claims à mão.
 *
 * Escreve nos DOIS sítios, e ambos são precisos: as custom claims (que
 * é o que as Security Rules e os guards das Cloud Functions leem — a
 * autoridade real) e o documento de staff (que é o que a UI lista).
 * Escrever só no documento daria um Gestor que a app mostra como Gestor
 * e que o servidor recusa.
 *
 * **As claims só chegam ao cliente no próximo token.** O Firebase Auth
 * renova-o passado cerca de uma hora, ou imediatamente a seguir a um
 * login novo — daí revogarmos os refresh tokens no fim: força a
 * renovação, e uma despromoção passa a valer já em vez de daqui a uma
 * hora.
 */
export const updateStaffRoles = onCall(async (request) => {
  const caller = requireManager(request);
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'updateStaffRoles',
    maxCalls: 20,
    windowSeconds: 300,
  });

  const { staffId, roles } = parseInput(inputSchema, request.data);

  // Um Gestor não se despromove a si próprio. Sem esta trava, o único
  // Gestor de um ginásio consegue tirar-se o papel e ficar sem forma de
  // o recuperar dentro da app — precisaria exatamente do developer que
  // esta função existe para dispensar.
  if (staffId === caller.uid && !roles.includes('manager')) {
    throw new HttpsError(
      'failed-precondition',
      'Não podes retirar o teu próprio papel de Gestor. Pede a outro '
        + 'Gestor para o fazer.',
    );
  }

  const firestore = getFirestore();
  const staffRef = firestore
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('staff')
    .doc(staffId);

  const snapshot = await staffRef.get();
  if (!snapshot.exists) {
    throw new HttpsError(
      'not-found',
      'Este membro do staff não pertence a este ginásio.',
    );
  }

  const auth = getAuth();
  await auth.setCustomUserClaims(staffId, {
    tenantId: caller.tenantId,
    roles,
  });

  await staffRef.set(
    {
      roles,
      rolesUpdatedAt: FieldValue.serverTimestamp(),
      rolesUpdatedBy: caller.uid,
    },
    { merge: true },
  );

  await auth.revokeRefreshTokens(staffId).catch(() => undefined);

  return { staffId, roles };
});
