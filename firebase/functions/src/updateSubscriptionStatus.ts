import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  subscriptionId: z.string().min(1),
  status: z.enum(['active', 'paused', 'cancelled', 'expired']),
});

/**
 * Fase 11 — mudar o estado de uma subscrição (cancelar, pausar,
 * reativar).
 *
 * Lacuna encontrada a rever os poderes do Gestor: dava para ATRIBUIR um
 * plano e nunca para lhe mexer. Uma subscrição ficava ativa para
 * sempre. Consequências reais:
 *
 * - Um aluno que saísse do ginásio continuava com plano ativo, a contar
 *   como elegível para marcar.
 * - Pior: `createSubscription` recusa um plano que colida no mesmo
 *   `exclusiveGroup`, e o ecrã de atribuição dizia "para trocar de
 *   nível, cancela primeiro o plano atual" — uma instrução que era
 *   impossível de cumprir dentro da app. Trocar de Standard para Plus
 *   exigia um developer.
 *
 * Cloud Function e não escrita direta porque `firestore.rules` bloqueia
 * toda a escrita em `subscriptions` (`allow write: if false`) desde a
 * Fase 3 — a criação sempre passou por função, e a mudança de estado
 * não tinha razão para ser diferente.
 *
 * **Não cascateia para as marcações já feitas**, e é deliberado: o
 * membro tinha o direito quando marcou, e apagar-lhe uma aula da semana
 * que vem porque mudou de plano seria uma surpresa desagradável. Para
 * tirar alguém de uma sessão existe `removeMembersFromOccurrence`, que
 * é uma decisão explícita e devolve a vaga.
 */
export const updateSubscriptionStatus = onCall(async (request) => {
  const caller = requireManager(request);
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'updateSubscriptionStatus',
    maxCalls: 30,
    windowSeconds: 300,
  });

  const { subscriptionId, status } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const subscriptionRef = firestore
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('subscriptions')
    .doc(subscriptionId);

  const snapshot = await subscriptionRef.get();
  if (!snapshot.exists) {
    throw new HttpsError(
      'not-found',
      'Subscrição não encontrada neste ginásio.',
    );
  }

  await subscriptionRef.set(
    {
      status,
      statusUpdatedAt: FieldValue.serverTimestamp(),
      statusUpdatedBy: caller.uid,
      // Guardar QUANDO acabou, e não só que acabou: um relatório de
      // faturação ou uma conversa com o aluno seis meses depois precisa
      // da data, e o `statusUpdatedAt` sozinho perde-se se o estado
      // voltar a mudar.
      ...(status === 'cancelled' || status === 'expired'
        ? { endedAt: FieldValue.serverTimestamp() }
        : {}),
      ...(status === 'active' ? { endedAt: FieldValue.delete() } : {}),
    },
    { merge: true },
  );

  return { subscriptionId, status };
});
