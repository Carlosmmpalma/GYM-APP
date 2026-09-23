import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { encontrarSobreposicao, erroDeSobreposicao } from './lib/overlap';
import { enforceRateLimit } from './lib/rateLimit';
import {
  isContentionError,
  resolveEligibility,
  runBookingTransaction,
} from './lib/bookingLogic';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberId: z.string().min(1),
});

/**
 * Fase 4 (guia-desenvolvimento.md) — migra `createBooking` de transação
 * client-side (Fase 2) para Cloud Function (Admin SDK), mesmo motivo de
 * `createSubscription` (Fase 3): a partir de agora a transação também
 * precisa de validar o limite semanal de utilização
 * (`usage/{memberId}_{serviceId}_{period}`), e a leitura desse
 * documento não pode ser confiada só a Security Rules com a mesma
 * robustez de código normal — Firestore Data Model v1 §52 já pede
 * explicitamente autoridade no backend para "limite semanal" e
 * "antecedência mínima". Fecha também uma lacuna já documentada no
 * código antigo (`firebase_booking_repository.dart`, nota removida
 * nesta fase): um cliente malicioso já não consegue, nem em teoria,
 * escrever `activeBookingCount` sem criar o `Booking` a par — as
 * Security Rules passam a negar escrita direta a ambos (ver
 * `firestore.rules`).
 *
 * Fase 5 — a leitura de elegibilidade e a transação em si passaram
 * para `lib/bookingLogic.ts` (`resolveEligibility`/
 * `runBookingTransaction`), partilhadas agora com
 * `generateRecurringOccurrences.ts`/`assignMembersToOccurrence.ts`.
 * Comportamento inalterado para este caminho — só a lógica mudou de
 * sítio.
 *
 * Self-service só (`BookingSource.self`) — atribuição manual por
 * Instrutor/Gestor usa os dois ficheiros novos da Fase 5, não este;
 * por isso usa `requireAuthenticated`, não `requireManager`, mas ainda
 * assim verifica `memberId === caller.uid` como defesa em profundidade
 * (o parâmetro existe porque o repository Dart já o passava desde a
 * Fase 2, não é decorativo).
 */
export const createBooking = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  // marcar 30 vezes num minuto não é uma pessoa a usar a app
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'createBooking',
    maxCalls: 30,
    windowSeconds: 60,
  });

  const { occurrenceId, memberId } = parseInput(inputSchema, request.data);

  if (memberId !== caller.uid) {
    throw new HttpsError(
      'permission-denied',
      'Só podes marcar uma sessão para ti próprio.',
    );
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef.collection('sessionOccurrences').doc(occurrenceId);
  const bookingRef = occurrenceRef.collection('bookings').doc(memberId);

  const occurrenceSnap = await occurrenceRef.get();
  if (!occurrenceSnap.exists) {
    throw new HttpsError('not-found', 'Esta sessão já não está disponível.');
  }
  const occurrenceData = occurrenceSnap.data()!;
  const serviceId = occurrenceData.serviceId as string;
  const startAt = (occurrenceData.startAt as Timestamp).toDate();

  // UC06/UC07/UC08/UC09 (fechado) — "antecedência mínima para marcar,
  // configurável pelo Gestor". Mesmo documento de `cancelBooking.ts`
  // (`config/bookingPolicy`), campo irmão — só se aplica aqui
  // (self-service): atribuição manual por Instrutor/Gestor
  // (`assignMembersToOccurrence.ts`) nunca passa por isto.
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
      'Não tens um plano ativo que dê acesso a este serviço.',
    );
  }

  // Ninguém está em dois sítios ao mesmo tempo. É a única regra de
  // combinação que a app impõe — ver `lib/overlap.ts` sobre porque
  // substituiu a que existia antes (`exclusiveGroup`).
  //
  // Antes da transação de propósito: é uma leitura, e falhar aqui não
  // toca em contador nenhum.
  const endAt = (occurrenceData.endAt as Timestamp | undefined)?.toDate();
  if (endAt) {
    const sobreposta = await encontrarSobreposicao(firestore, tenantRef, {
      memberId,
      inicio: startAt,
      fim: endAt,
      excluirOccurrenceId: occurrenceId,
    });
    if (sobreposta) throw erroDeSobreposicao(sobreposta);
  }

  // Uma transação que esgota as tentativas sobe daqui como uma exceção
  // qualquer, e o Firebase embrulha-a em `internal` — ao aluno chega uma
  // mensagem genérica de erro, numa aula que pode ter lugares.
  //
  // Isto acontece quando muita gente marca a MESMA aula ao mesmo tempo:
  // todas as marcações disputam o documento onde vive o contador. Medido
  // contra o emulador, com trinta em simultâneo e as quinze tentativas
  // que `runBookingTransaction` já faz, não voltou a acontecer — mas
  // "não voltou a acontecer" não é "não acontece", e a diferença entre
  // "não deu, tenta outra vez" e um erro genérico é a diferença entre a
  // pessoa tentar e desistir.
  let result;
  try {
    result = await runBookingTransaction(firestore, {
      tenantRef,
      occurrenceRef,
      bookingRef,
      memberId,
      serviceId,
      startAt,
      source: 'self',
      eligibility,
    });
  } catch (error) {
    if (isContentionError(error)) {
      throw new HttpsError(
        'aborted',
        'Está muita gente a marcar esta aula ao mesmo tempo. Tenta outra '
          + 'vez — ainda pode haver lugar.',
        { reason: 'contention' },
      );
    }
    throw error;
  }

  switch (result.kind) {
    case 'booked':
      return { booked: true };
    case 'already-booked':
      throw new HttpsError(
        'already-exists',
        'Já tens uma marcação nesta sessão.',
        { reason: 'already-booked' },
      );
    case 'capacity':
      throw new HttpsError(
        'resource-exhausted',
        'Já não há vagas — a aula ficou cheia entretanto.',
        { reason: 'capacity' },
      );
    case 'not-found':
      throw new HttpsError('not-found', 'Esta sessão já não está disponível.');
    case 'usage-limit':
      throw new HttpsError(
        'resource-exhausted',
        `Já atingiste o limite semanal deste serviço (${result.used}/${result.limit}).`,
        { reason: 'usage-limit', used: result.used, limit: result.limit },
      );
  }
});
