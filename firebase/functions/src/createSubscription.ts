import { FieldValue, FieldPath, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';

const inputSchema = z.object({
  memberId: z.string().min(1),
  planId: z.string().min(1),
  agreedPrice: z.number().nonnegative(),
  currency: z.string().min(1),
});

/**
 * Fase 3 (guia-desenvolvimento.md) — "Cloud Function createSubscription:
 * valida regra 'uma subscription ativa por serviço'".
 *
 * Corre como Cloud Function (Admin SDK), não como transação
 * client-side (ao contrário de createBooking/cancelBooking na Fase 2):
 * a validação "o membro já tem outra subscription ativa que dá acesso
 * a um destes serviços" (Domain Model v1 §15) precisa de percorrer
 * TODAS as subscriptions ativas do membro — um número variável de
 * documentos, não uma comparação de campos dentro de UM documento como
 * na Fase 2. Ver nota equivalente em
 * lib/infrastructure/firebase/firebase_subscription_repository.dart.
 *
 * Só um Gestor do próprio tenant pode chamar isto (requireManager) —
 * mesmo padrão de createMember/createStaff.
 *
 * Fase 8 (auditoria funcional, UC26 fechado) — "Sem acompanhamento" e
 * Standard/Plus/Premium não são produtos independentes, são NÍVEIS DO
 * MESMO PRODUTO: passou a validar também conflito por
 * `Service.exclusiveGroup`, não só por `serviceId` literal — dois
 * planos que concedem serviços DIFERENTES mas com o mesmo
 * `exclusiveGroup` são tratados como o mesmo conflito.
 */
export const createSubscription = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { memberId, planId, agreedPrice, currency } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  const memberSnap = await tenantRef.collection('members').doc(memberId).get();
  if (!memberSnap.exists) {
    throw new HttpsError('not-found', 'Membro não encontrado neste tenant.');
  }

  const planRef = tenantRef.collection('plans').doc(planId);
  const planSnap = await planRef.get();
  if (!planSnap.exists) {
    throw new HttpsError('not-found', 'Plano não encontrado neste tenant.');
  }
  if (planSnap.data()?.active === false) {
    throw new HttpsError('failed-precondition', 'Este plano já não está ativo.');
  }

  // Domain Model v1 §12 — os serviços concedidos por este Plan.
  const planServicesSnap = await planRef
    .collection('services')
    .where('enabled', '==', true)
    .get();
  const grantedServiceIds = planServicesSnap.docs.map((doc) => doc.id);

  if (grantedServiceIds.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'Este plano ainda não tem nenhum serviço associado.',
    );
  }

  // Domain Model v1 §15 — "por defeito, um membro não pode possuir
  // simultaneamente duas subscriptions ativas que concedam acesso ao
  // mesmo Service". Percorre as subscriptions ATIVAS existentes do
  // membro e verifica interseção de activeServiceIds.
  const existingActiveSnap = await tenantRef
    .collection('subscriptions')
    .where('memberId', '==', memberId)
    .where('status', '==', 'active')
    .get();

  // UC26 (fechado) — "Sem acompanhamento" e Standard/Plus/Premium são
  // NÍVEIS DO MESMO PRODUTO, nunca combináveis, mesmo quando são
  // serviços DIFERENTES (o `activeServiceIds` acima só apanhava o
  // membro a repetir o MESMO serviço). Antes de comparar, é preciso
  // saber o `exclusiveGroup` de cada serviço envolvido — tanto os que
  // este plano concederia como os que as subscriptions ativas já
  // concedem — daí ter de ler `services` já aqui, não só no caminho de
  // erro como o conflito por serviço fazia até agora.
  const existingServiceIds = new Set<string>();
  for (const doc of existingActiveSnap.docs) {
    for (const id of (doc.data().activeServiceIds as string[]) ?? []) {
      existingServiceIds.add(id);
    }
  }
  const allServiceIds = [...new Set([...grantedServiceIds, ...existingServiceIds])];

  const serviceInfoById = new Map<string, { name: string; exclusiveGroup: string | null }>();
  for (let i = 0; i < allServiceIds.length; i += 30) {
    // 'in' aceita no máximo 30 valores (limite da SDK).
    const chunk = allServiceIds.slice(i, i + 30);
    const chunkSnap = await tenantRef
      .collection('services')
      .where(FieldPath.documentId(), 'in', chunk)
      .get();
    for (const doc of chunkSnap.docs) {
      serviceInfoById.set(doc.id, {
        name: (doc.data().name as string | undefined) ?? doc.id,
        exclusiveGroup: (doc.data().exclusiveGroup as string | undefined) ?? null,
      });
    }
  }

  const newExclusiveGroups = new Set(
    grantedServiceIds
      .map((id) => serviceInfoById.get(id)?.exclusiveGroup)
      .filter((g): g is string => !!g),
  );

  const conflictingServiceIds = new Set<string>();
  for (const doc of existingActiveSnap.docs) {
    for (const serviceId of (doc.data().activeServiceIds as string[]) ?? []) {
      const sameService = grantedServiceIds.includes(serviceId);
      const group = serviceInfoById.get(serviceId)?.exclusiveGroup;
      const sameGroup = !!group && newExclusiveGroups.has(group);
      if (sameService || sameGroup) {
        conflictingServiceIds.add(serviceId);
      }
    }
  }

  if (conflictingServiceIds.size > 0) {
    const conflictingServiceNames = [...conflictingServiceIds].map(
      (id) => serviceInfoById.get(id)?.name ?? id,
    );

    throw new HttpsError(
      'already-exists',
      'O membro já tem acesso a um ou mais destes serviços através de ' +
        'outra subscription ativa.',
      { conflictingServiceNames },
    );
  }

  const subscriptionRef = tenantRef.collection('subscriptions').doc();
  await subscriptionRef.set({
    memberId,
    planId,
    status: 'active',
    startDate: FieldValue.serverTimestamp(),
    endDate: null,
    agreedPrice,
    currency,
    activeServiceIds: grantedServiceIds,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: caller.uid,
  });

  return { subscriptionId: subscriptionRef.id };
});
