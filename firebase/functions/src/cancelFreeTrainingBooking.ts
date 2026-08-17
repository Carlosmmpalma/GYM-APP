import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';

const inputSchema = z.object({
  weekId: z.string().min(1),
  slotId: z.string().min(1),
  memberId: z.string().min(1),
});

/**
 * Fase 7 — cancelar uma marcação de treino livre. Mesma lógica de
 * `cancelBooking.ts` (janela de antecedência mínima via
 * `config/bookingPolicy`, vaga sempre libertada, usage só devolvida
 * dentro da janela) — duplicada aqui em vez de partilhada porque
 * `cancelBooking.ts` já não usa `lib/bookingLogic.ts` para a fase de
 * libertação (a janela de antecedência é específica do cancelamento
 * pelo PRÓPRIO membro, distinta de `prepareRelease`/`applyRelease`,
 * que são sempre-devolve, estúdio-iniciado — ver Fase 6); refatorar
 * `cancelBooking.ts` para partilhar isto arriscaria mexer em código já
 * testado sem necessidade.
 */
export const cancelFreeTrainingBooking = onCall(async (request) => {
  const caller = requireAuthenticated(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { weekId, slotId, memberId } = parsed.data;

  if (memberId !== caller.uid) {
    throw new HttpsError('permission-denied', 'Só podes cancelar uma marcação tua.');
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const slotRef = tenantRef
    .collection('freeTrainingSchedules')
    .doc(weekId)
    .collection('slots')
    .doc(slotId);
  const bookingRef = slotRef.collection('bookings').doc(memberId);

  const policySnap = await tenantRef.collection('config').doc('bookingPolicy').get();
  const minNoticeHours =
    (policySnap.data()?.minCancellationNoticeHours as number | undefined) ?? 0;

  const result = await firestore.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    const slotSnap = await tx.get(slotRef);

    if (!bookingSnap.exists || bookingSnap.data()?.status !== 'booked') {
      return { found: false, usageRefunded: false };
    }
    const bookingData = bookingSnap.data()!;

    const startAt = (slotSnap.data()?.startAt as FirebaseFirestore.Timestamp | undefined)
      ?.toDate();
    const hoursUntilStart = startAt
      ? (startAt.getTime() - Date.now()) / (60 * 60 * 1000)
      : -Infinity;
    const withinWindow = minNoticeHours <= 0 || hoursUntilStart >= minNoticeHours;

    const serviceId = bookingData.serviceId as string | undefined;
    const period = bookingData.period as string | undefined;
    // UC08-A — mesma correção de `lib/bookingLogic.ts#prepareRelease` e
    // `cancelBooking.ts`: sessão extra nunca incrementou `usage`, logo
    // cancelá-la não pode decrementar.
    const isExtra = (bookingData.isExtra as boolean | undefined) ?? false;
    const usageRef =
      withinWindow && serviceId && period && !isExtra
        ? tenantRef.collection('usage').doc(`${memberId}_${serviceId}_${period}`)
        : null;
    const usageSnap = usageRef ? await tx.get(usageRef) : null;

    const activeCount = (slotSnap.data()?.activeBookingCount as number | undefined) ?? 0;

    tx.update(bookingRef, {
      status: 'cancelled',
      cancelledAt: FieldValue.serverTimestamp(),
    });
    tx.update(slotRef, {
      activeBookingCount: activeCount > 0 ? activeCount - 1 : 0,
    });

    let usageRefunded = false;
    if (usageRef && usageSnap?.exists) {
      const used = (usageSnap.data()?.used as number | undefined) ?? 0;
      tx.update(usageRef, {
        used: used > 0 ? used - 1 : 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
      usageRefunded = true;
    }

    return { found: true, usageRefunded };
  });

  if (!result.found) {
    throw new HttpsError('not-found', 'Não tens uma marcação ativa neste horário.');
  }

  return { cancelled: true, usageRefunded: result.usageRefunded };
});
