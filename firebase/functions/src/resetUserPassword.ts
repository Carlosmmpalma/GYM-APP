import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { generateTemporaryPassword } from './lib/tempPassword';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  userId: z.string().min(1),
});

/**
 * Fase 11 — o Gestor repõe a password de qualquer membro ou staff do
 * seu ginásio.
 *
 * É o pedido mais banal ao balcão de um ginásio ("esqueci-me da
 * password") e até aqui não tinha resposta nenhuma dentro da app: os
 * membros autenticam-se com um email SINTÉTICO, que não existe em lado
 * nenhum e ao qual não se pode enviar um link de recuperação. Sem isto,
 * cada esquecimento obrigava a mexer no Firebase à mão.
 *
 * Gera uma password temporária e marca `passwordTemporaria: true`, tal
 * como `createMember`/`createStaff` fazem: a pessoa entra com ela e a
 * app força a troca no primeiro arranque (UC22). O Gestor entrega-a em
 * mão — que é a verificação de identidade que faz sentido num ginásio,
 * onde a pessoa está à frente dele.
 *
 * Funciona para os dois tipos de conta pela mesma via, e é deliberado:
 * um `sendPasswordResetEmail` só serviria para staff (email real) e
 * dependeria de entrega de email para uma operação que tem de funcionar
 * com a pessoa à espera.
 *
 * Recusa repor a password do PRÓPRIO Gestor: para isso existe a troca
 * de password normal, e um Gestor que se tranque a si mesmo fora da
 * conta com uma password que não anotou fica sem forma de entrar.
 */
export const resetUserPassword = onCall(async (request) => {
  const caller = requireManager(request);
  // Operação de balcão: repete-se poucas vezes por dia, e cada chamada
  // invalida a password de alguém.
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'resetUserPassword',
    maxCalls: 20,
    windowSeconds: 300,
  });

  const { userId } = parseInput(inputSchema, request.data);

  if (userId === caller.uid) {
    throw new HttpsError(
      'failed-precondition',
      'Para mudares a tua própria password usa a opção de troca de ' +
        'password, não esta.',
    );
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  // O utilizador tem de pertencer a ESTE tenant — nunca confiamos no
  // `userId` vindo do cliente para decidir isso.
  const [memberSnapshot, staffSnapshot] = await Promise.all([
    tenantRef.collection('members').doc(userId).get(),
    tenantRef.collection('staff').doc(userId).get(),
  ]);

  const targetRef = memberSnapshot.exists
    ? memberSnapshot.ref
    : staffSnapshot.exists
      ? staffSnapshot.ref
      : null;

  if (!targetRef) {
    throw new HttpsError(
      'not-found',
      'Este utilizador não pertence a este ginásio.',
    );
  }

  const temporaryPassword = generateTemporaryPassword();
  const auth = getAuth();

  try {
    await auth.updateUser(userId, { password: temporaryPassword });
  } catch (error) {
    throw new HttpsError(
      'not-found',
      'Não foi possível repor a password: a conta de acesso não existe.',
    );
  }

  await targetRef.set(
    {
      passwordTemporaria: true,
      passwordResetAt: FieldValue.serverTimestamp(),
      passwordResetBy: caller.uid,
    },
    { merge: true },
  );

  // Revogar os refresh tokens fecha as sessões abertas noutros
  // dispositivos. Se a razão da reposição for uma conta comprometida,
  // deixar a sessão antiga viva tornaria a reposição inútil.
  await auth.revokeRefreshTokens(userId).catch(() => undefined);

  return { temporaryPassword };
});
