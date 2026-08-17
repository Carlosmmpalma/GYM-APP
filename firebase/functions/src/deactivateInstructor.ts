import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { applyRelease, prepareRelease, ReleasePlan } from './lib/bookingLogic';
import { notifyMembers } from './lib/notifications';

const inputSchema = z.object({
  staffId: z.string().min(1),
});

/**
 * Fase 6 (UC24) — "desativação de instrutor → cancela automaticamente
 * as suas sessões futuras". Manager-only (gestão de staff continua
 * exclusiva do Gestor, ao contrário das operações do dia a dia sobre
 * uma sessão já criada). Três coisas, nesta ordem:
 *
 *   1. `staff/{id}.status = inactive`.
 *   2. Todas as `sessionSeries` deste instrutor com `status: active`
 *      passam a `cancelled` — deixam de gerar novas ocorrências (mesmo
 *      efeito de `SessionSeriesRepository.cancelSeries`, só que aqui
 *      abrange TODAS as séries do instrutor, não uma escolhida).
 *   3. Cada ocorrência futura ainda `scheduled` deste instrutor
 *      (independente de vir de série ou ser ad-hoc) é cancelada com a
 *      MESMA cascata de `cancelOccurrenceForStudio.ts` (bookings
 *      libertados, usage sempre devolvida).
 *
 * Passo 1+2 numa única `WriteBatch` (sem invariante cross-documento a
 * proteger, só queremos as duas coisas juntas). Passo 3 é uma
 * transação POR OCORRÊNCIA (não dá para juntar N ocorrências, cada
 * uma com a sua subcoleção de bookings, numa única transação Firestore
 * de forma escalável) — corridas sequencialmente, mesmo padrão de
 * `generateRecurringOccurrences.ts` ao percorrer múltiplas séries.
 */
export const deactivateInstructor = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { staffId } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const staffRef = tenantRef.collection('staff').doc(staffId);

  const staffSnap = await staffRef.get();
  if (!staffSnap.exists) {
    throw new HttpsError('not-found', 'Staff não encontrado neste tenant.');
  }

  // Passo 1+2 — staff inativo + séries dele canceladas, na mesma escrita.
  const seriesSnap = await tenantRef
    .collection('sessionSeries')
    .where('instructorId', '==', staffId)
    .get();
  const activeSeriesDocs = seriesSnap.docs.filter(
    (doc) => (doc.data().status as string | undefined) !== 'cancelled',
  );

  const batch = firestore.batch();
  batch.update(staffRef, { status: 'inactive' });
  for (const doc of activeSeriesDocs) {
    batch.update(doc.ref, { status: 'cancelled' });
  }
  await batch.commit();

  // Passo 3 — cascata por ocorrência futura ainda agendada.
  const now = new Date();
  const occurrencesSnap = await tenantRef
    .collection('sessionOccurrences')
    .where('instructorId', '==', staffId)
    .where('startAt', '>=', now)
    .get();
  const scheduledOccurrences = occurrencesSnap.docs.filter(
    (doc) => (doc.data().status as string | undefined) === 'scheduled',
  );

  let cancelledOccurrences = 0;
  let cancelledBookings = 0;
  const affectedMemberIds = new Set<string>();
  for (const occDoc of scheduledOccurrences) {
    const occurrenceRef = occDoc.ref;
    const result = await firestore.runTransaction(async (tx) => {
      const activeBookingsSnap = await tx.get(
        occurrenceRef.collection('bookings').where('status', '==', 'booked'),
      );
      const plans: ReleasePlan[] = [];
      for (const bookingDoc of activeBookingsSnap.docs) {
        const plan = await prepareRelease(tx, {
          tenantRef,
          occurrenceRef,
          memberId: bookingDoc.id,
        });
        if (plan) plans.push(plan);
      }
      for (const plan of plans) {
        applyRelease(tx, plan);
      }
      tx.update(occurrenceRef, { status: 'cancelled', activeBookingCount: 0 });
      return plans.map((p) => p.memberId);
    });
    cancelledOccurrences += 1;
    cancelledBookings += result.length;
    for (const memberId of result) affectedMemberIds.add(memberId);
  }

  // UC24 (fechado) — "alunos notificados e sessões devolvidas ao limite
  // semanal". UMA notificação por aluno afetado, não uma por ocorrência
  // cancelada: um aluno com 8 sessões semanais deste instrutor receberia
  // 8 pushes idênticos, o que seria spam. Por isso o `Set` acima.
  if (affectedMemberIds.size > 0) {
    await notifyMembers(
      tenantRef,
      [...affectedMemberIds],
      'Sessões canceladas',
      'O instrutor destas sessões deixou de estar disponível. As tuas '
        + 'marcações futuras com ele foram canceladas e voltaram ao teu '
        + 'limite semanal.',
    );
  }

  return {
    seriesCancelled: activeSeriesDocs.length,
    occurrencesCancelled: cancelledOccurrences,
    bookingsCancelled: cancelledBookings,
    membersNotified: affectedMemberIds.size,
  };
});
