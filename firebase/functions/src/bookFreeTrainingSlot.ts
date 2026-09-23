import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { encontrarSobreposicao, erroDeSobreposicao } from './lib/overlap';
import { enforceRateLimit } from './lib/rateLimit';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';
import { parseInput } from './lib/validation';

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

  const { weekId, slotId, memberId } = parseInput(inputSchema, request.data);

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
  // A outra ponta da mesma janela: não marcar demasiado longe.
  //
  // As séries geram ocorrências com 8 semanas de antecedência para o
  // estúdio planear; deixar o aluno marcar todas ocupa vagas que
  // ninguém mais pode usar, para aulas de que ele já não se vai
  // lembrar. `0` = sem limite (o valor por omissão, para não mudar o
  // comportamento de quem já usa a app sem saber desta definição).
  //
  // Validado aqui e não só no ecrã: o ecrã esconde as aulas fora do
  // horizonte, mas esconder não é impedir — um pedido direto à função
  // continuava a passar.
  const horizonDays =
    (policySnap.data()?.bookingHorizonDays as number | undefined) ?? 0;
  if (horizonDays > 0) {
    const limite = new Date();
    limite.setDate(limite.getDate() + horizonDays);
    if (startAt > limite) {
      throw new HttpsError(
        'failed-precondition',
        `Só é possível marcar com ${horizonDays} dia(s) de antecedência.`,
        { reason: 'beyond-horizon', horizonDays },
      );
    }
  }

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

  // A mesma regra das aulas: ninguém está em dois sítios ao mesmo
  // tempo. Um bloco de treino livre e uma aula cruzam-se tal como duas
  // aulas se cruzam — ver `lib/overlap.ts`.
  const endAt = (slotData.endAt as Timestamp | undefined)?.toDate();
  if (endAt) {
    const sobreposta = await encontrarSobreposicao(firestore, tenantRef, {
      memberId,
      inicio: startAt,
      fim: endAt,
      excluirOccurrenceId: slotId,
    });
    if (sobreposta) throw erroDeSobreposicao(sobreposta);
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
