import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { applyRelease, prepareRelease, ReleasePlan } from './lib/bookingLogic';
import { describeOccurrence, notifyMembers } from './lib/notifications';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
});

/**
 * Fase 6 (UC18/UC10) — "Cancelamento de sessão pelo estúdio → cancela
 * bookings + devolve usage em cadeia". Até esta fase,
 * `SessionOccurrenceRepository.cancelOccurrence` (Fase 5) era uma
 * escrita direta do cliente que só mudava `status`, sem tocar em
 * nenhum booking — a própria Fase 5 já tinha assinalado isto como
 * lacuna ("isso é Fase 6"). Substitui essa implementação por completo
 * (`firestore.rules` já bloqueia mudar `status` por escrita direta,
 * mesmo para Manager).
 *
 * Cancela TODOS os bookings ativos (usage sempre devolvida, mesmo
 * raciocínio de `removeMembersFromOccurrence`) e só depois marca a
 * ocorrência como `cancelled`. Manager OU Instrutor.
 */
export const cancelOccurrenceForStudio =
    onCall({ timeoutSeconds: 120 }, async (request) => {
  const caller = requireManagerOrInstructor(request);

  const { occurrenceId } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef.collection('sessionOccurrences').doc(occurrenceId);

  const result = await firestore.runTransaction(async (tx) => {
    const occSnap = await tx.get(occurrenceRef);
    if (!occSnap.exists) {
      throw new HttpsError('not-found', 'Esta sessão já não está disponível.');
    }

    // Todas as leituras primeiro: a lista de bookings ativos + um
    // `prepareRelease` por cada um.
    const activeBookingsSnap = await tx.get(
      occurrenceRef.collection('bookings').where('status', '==', 'booked'),
    );
    const plans: ReleasePlan[] = [];
    for (const doc of activeBookingsSnap.docs) {
      const plan = await prepareRelease(tx, { tenantRef, occurrenceRef, memberId: doc.id });
      if (plan) plans.push(plan);
    }

    for (const plan of plans) {
      applyRelease(tx, plan);
    }
    tx.update(occurrenceRef, { status: 'cancelled', activeBookingCount: 0 });

    return {
      cancelledBookings: plans.length,
      memberIds: plans.map((p) => p.memberId),
      startAt: (occSnap.data()?.startAt as Timestamp | undefined)?.toDate(),
    };
  });

  // UC10/UC18 (fechado) — o estúdio cancelou a aula; quem estava
  // inscrito é notificado (UC11). Fora da transação, e sem poder
  // desfazer o cancelamento se falhar (ver `lib/notifications.ts`).
  if (result.memberIds.length > 0) {
    const when = result.startAt ? describeOccurrence(result.startAt) : 'uma sessão marcada';
    await notifyMembers(
      tenantRef,
      result.memberIds,
      'Sessão cancelada',
      `A sessão de ${when} foi cancelada pelo estúdio. A sessão volta ao teu limite semanal.`,
    );
  }

  return { cancelledBookings: result.cancelledBookings };
});
