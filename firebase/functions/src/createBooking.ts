import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';

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

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { occurrenceId, memberId } = parsed.data;

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

  const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);
  if (!eligibility) {
    throw new HttpsError(
      'permission-denied',
      'Não tens um plano ativo que dê acesso a este serviço.',
    );
  }

  const result = await runBookingTransaction(firestore, {
    tenantRef,
    occurrenceRef,
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
