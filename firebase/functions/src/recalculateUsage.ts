import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { isoWeekKeyToMonday, isoWeekRange } from './lib/isoWeek';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  memberId: z.string().min(1),
  serviceId: z.string().min(1),
});

/**
 * Fase 4 story 6 — "Cloud Function de reconciliação: recalcula usage a
 * partir dos bookings reais (ferramenta de operação, não só teoria)".
 *
 * `usage` é um read model derivado (Firestore Data Model v1 §32/D13),
 * nunca a fonte de verdade — isto reconstrói
 * `usage/{memberId}_{serviceId}_{period}` a partir dos `Booking`s reais
 * (`status == 'booked' && isExtra == false`), agrupados por `period`
 * (denormalizado no booking desde a Fase 4 — ver `booking.dart`).
 * Bookings anteriores a esta fase (sem `serviceId`/`period`) são
 * ignorados — nunca tinham incrementado usage nenhum, para começar.
 *
 * Só Manager (ferramenta administrativa, sem UI de aluno). Recalcula
 * SEMPRE a totalidade de períodos já tocados para este membro+serviço
 * — incluindo os que ficaram a zero entretanto (ex.: as duas
 * marcações desse período foram canceladas) — não só os períodos com
 * bookings ativos agora, senão um `usage` "esquecido" em 2 nunca seria
 * corrigido de volta para 0.
 */
export const recalculateUsage = onCall(async (request) => {
  const caller = requireManager(request);
  // varre todas as marcações de um membro
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'recalculateUsage',
    maxCalls: 10,
    windowSeconds: 300,
  });

  const { memberId, serviceId } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  // `collectionGroup('bookings')` filtrado só por `memberId` (sem
  // restringir tenant explicitamente no path) é seguro pelo mesmo
  // motivo já documentado em `watchMyBookings`
  // (`firebase_booking_repository.dart`): um uid do Firebase Auth só
  // pertence a UM tenant (custom claim `tenantId` singular) — nunca há
  // bookings de outro tenant com este `memberId`. Precisa do índice
  // composto declarado em `firestore.indexes.json`.
  const bookingsSnap = await firestore
    .collectionGroup('bookings')
    .where('memberId', '==', memberId)
    .where('serviceId', '==', serviceId)
    .where('status', '==', 'booked')
    .where('isExtra', '==', false)
    .get();

  const countsByPeriod = new Map<string, number>();
  for (const doc of bookingsSnap.docs) {
    const period = doc.data().period as string | undefined;
    if (!period) continue;
    countsByPeriod.set(period, (countsByPeriod.get(period) ?? 0) + 1);
  }

  const existingUsageSnap = await tenantRef
    .collection('usage')
    .where('memberId', '==', memberId)
    .where('serviceId', '==', serviceId)
    .get();
  const periodsToReconcile = new Set<string>(countsByPeriod.keys());
  for (const doc of existingUsageSnap.docs) {
    const period = doc.data().period as string | undefined;
    if (period) periodsToReconcile.add(period);
  }

  const results: Array<{ period: string; used: number }> = [];
  const batch = firestore.batch();
  for (const period of periodsToReconcile) {
    const used = countsByPeriod.get(period) ?? 0;
    const { start, end } = isoWeekRange(isoWeekKeyToMonday(period));
    const usageRef = tenantRef.collection('usage').doc(`${memberId}_${serviceId}_${period}`);
    batch.set(
      usageRef,
      {
        memberId,
        serviceId,
        period,
        periodType: 'week',
        periodStart: Timestamp.fromDate(start),
        periodEnd: Timestamp.fromDate(end),
        used,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    results.push({ period, used });
  }
  await batch.commit();

  return { recalculated: results };
});
