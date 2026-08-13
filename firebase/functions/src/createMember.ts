import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { buildSyntheticEmail } from './lib/loginIdentifier';
import { nextMemberNumber } from './lib/memberNumber';
import { generateTemporaryPassword } from './lib/tempPassword';

const inputSchema = z.object({
  name: z.string().min(1),
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

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { name } = parsed.data;

  const firestore = getFirestore();
  const auth = getAuth();

  const memberNumber = await nextMemberNumber(firestore, caller.tenantId);
  const email = buildSyntheticEmail(caller.tenantId, memberNumber);
  const temporaryPassword = generateTemporaryPassword();

  const userRecord = await auth.createUser({
    email,
    password: temporaryPassword,
    displayName: name,
  });

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
      createdAt: FieldValue.serverTimestamp(),
      createdBy: caller.uid,
    });

  return {
    uid: userRecord.uid,
    memberNumber,
    temporaryPassword,
  };
});
