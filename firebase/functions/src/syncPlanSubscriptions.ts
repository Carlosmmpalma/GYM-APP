import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';

const inputSchema = z.object({
  planId: z.string().min(1),
});

/**
 * Fase 11 — repõe `activeServiceIds` das subscrições ATIVAS de um plano
 * a partir dos serviços que o plano dá hoje.
 *
 * **O bug que isto corrige.** `activeServiceIds` é uma cópia dos
 * serviços do plano, tirada no momento em que a subscrição é criada
 * (`createSubscription`) — e nada, em fase nenhuma, a voltava a tocar.
 * Consequência: acrescentar um serviço a um plano não fazia
 * absolutamente nada a quem já tinha esse plano.
 *
 * Apanhado a testar: o Gestor acrescenta "Treino Livre" ao plano da
 * aluna, e a app continua a dizer-lhe "o teu plano não inclui treino
 * livre". Não era da app — a subscrição dela continuava com a lista
 * antiga, e é essa lista que TUDO consulta: o filtro do ecrã, a
 * validação de `createBooking`, e a query de membros elegíveis.
 *
 * Porquê uma Cloud Function e não uma escrita direta: `firestore.rules`
 * bloqueia toda a escrita em `subscriptions` (`allow write: if false`)
 * desde a Fase 3.
 *
 * Porquê manter a cópia em vez de calcular na hora: a query
 * `where('activeServiceIds', 'array-contains', X)` — usada para listar
 * os membros elegíveis a um serviço — precisa do campo no documento.
 * Trocar isso obrigaria a ler o plano de cada subscrição a cada
 * consulta.
 *
 * **Não mexe em subscrições canceladas ou expiradas.** O que elas
 * concediam faz parte do histórico; reescrevê-lo seria falsificar o
 * passado.
 */
export const syncPlanSubscriptions = onCall(async (request) => {
  const caller = requireManager(request);
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'syncPlanSubscriptions',
    maxCalls: 30,
    windowSeconds: 300,
  });

  const { planId } = inputSchema.parse(request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const planRef = tenantRef.collection('plans').doc(planId);

  const planSnap = await planRef.get();
  if (!planSnap.exists) {
    throw new HttpsError('not-found', 'Plano não encontrado neste ginásio.');
  }

  const planServicesSnap = await planRef
    .collection('services')
    .where('enabled', '==', true)
    .get();
  const grantedServiceIds = planServicesSnap.docs.map((doc) => doc.id);

  const subscriptionsSnap = await tenantRef
    .collection('subscriptions')
    .where('planId', '==', planId)
    .where('status', '==', 'active')
    .get();

  let updated = 0;
  const batch = firestore.batch();
  for (const doc of subscriptionsSnap.docs) {
    const current = ((doc.get('activeServiceIds') as string[]) ?? [])
      .slice()
      .sort();
    const next = grantedServiceIds.slice().sort();
    // Só escreve o que mudou: evita gerar eventos e custo por
    // subscrições que já estavam certas.
    if (current.join('|') === next.join('|')) continue;

    batch.update(doc.ref, {
      activeServiceIds: grantedServiceIds,
      servicesSyncedAt: FieldValue.serverTimestamp(),
      servicesSyncedBy: caller.uid,
    });
    updated += 1;
  }

  if (updated > 0) await batch.commit();

  return {
    planId,
    grantedServiceIds,
    activeSubscriptions: subscriptionsSnap.size,
    updated,
  };
});
