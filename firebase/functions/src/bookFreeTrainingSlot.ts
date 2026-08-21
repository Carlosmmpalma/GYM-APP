import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';

const inputSchema = z.object({
  weekId: z.string().min(1),
  slotId: z.string().min(1),
  memberId: z.string().min(1),
});

/**
 * Fase 7 — marcar um bloco de treino livre. Praticamente idêntico a
 * `createBooking.ts` (mesma `resolveEligibility`/`runBookingTransaction`
 * de `lib/bookingLogic.ts`, só a apontar para
 * `freeTrainingSchedules/{weekId}/slots/{slotId}` em vez de
 * `sessionOccurrences/{id}`) — a diferença real é a verificação extra
 * de que a SEMANA está `published`: um slot pode existir (rascunho ou
 * sugestão ainda por aprovar) sem estar visível a ninguém fora do
 * Gestor; sem esta verificação no servidor, um aluno que de alguma
 * forma soubesse o `weekId`/`slotId` de uma semana não publicada
 * conseguiria marcar-se nela, contornando a Security Rule que só
 * bloqueia LEITURA de semanas não publicadas.
 */
export const bookFreeTrainingSlot = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  // mesmo raciocínio de createBooking
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'bookFreeTrainingSlot',
    maxCalls: 30,
    windowSeconds: 60,
  });

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { weekId, slotId, memberId } = parsed.data;

  if (memberId !== caller.uid) {
    throw new HttpsError('permission-denied', 'Só podes marcar um horário para ti próprio.');
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const scheduleRef = tenantRef.collection('freeTrainingSchedules').doc(weekId);
  const slotRef = scheduleRef.collection('slots').doc(slotId);
  const bookingRef = slotRef.collection('bookings').doc(memberId);

  const scheduleSnap = await scheduleRef.get();
  if (!scheduleSnap.exists || scheduleSnap.data()!.status !== 'published') {
    throw new HttpsError('failed-precondition', 'Esta semana ainda não está publicada.');
  }

  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Este horário já não está disponível.');
  }
  const slotData = slotSnap.data()!;
  const serviceId = slotData.serviceId as string;
  const startAt = (slotData.startAt as Timestamp).toDate();

  // UC06/UC07/UC08/UC09 (fechado) — mesma antecedência mínima de
  // `createBooking.ts`, só self-service (ver comentário lá).
  const policySnap = await tenantRef.collection('config').doc('bookingPolicy').get();
  const minNoticeMinutes =
    (policySnap.data()?.minBookingNoticeMinutes as number | undefined) ?? 0;
  const minutesUntilStart = (startAt.getTime() - Date.now()) / (60 * 1000);
  if (minNoticeMinutes > 0 && minutesUntilStart < minNoticeMinutes) {
    throw new HttpsError(
      'failed-precondition',
      `É preciso marcar com pelo menos ${minNoticeMinutes} minuto(s) de antecedência.`,
      { reason: 'too-close-to-start', minutesRequired: minNoticeMinutes },
    );
  }

  const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);
  if (!eligibility) {
    throw new HttpsError(
      'permission-denied',
      'Não tens um plano ativo que dê acesso a treino livre.',
    );
  }

  const result = await runBookingTransaction(firestore, {
    tenantRef,
    occurrenceRef: slotRef,
    bookingRef,
    memberId,
    serviceId,
    startAt,
    source: 'self',
    eligibility,
  });

  switch (result.kind) {
    case 'booked':
      return { booked: true };
    case 'already-booked':
      throw new HttpsError('already-exists', 'Já tens uma marcação neste horário.', {
        reason: 'already-booked',
      });
    case 'capacity':
      throw new HttpsError(
        'resource-exhausted',
        'Já não há vagas — o horário ficou cheio entretanto.',
        { reason: 'capacity' },
      );
    case 'not-found':
      throw new HttpsError('not-found', 'Este horário já não está disponível.');
    case 'usage-limit':
      throw new HttpsError(
        'resource-exhausted',
        `Já atingiste o limite semanal deste serviço (${result.used}/${result.limit}).`,
        { reason: 'usage-limit', used: result.used, limit: result.limit },
      );
  }
});
