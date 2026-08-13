import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { isoWeekKey, isoWeekRange } from './lib/isoWeek';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberId: z.string().min(1),
});

type TxResult =
  | { kind: 'booked' }
  | { kind: 'already-booked' }
  | { kind: 'capacity' }
  | { kind: 'not-found' }
  | { kind: 'usage-limit'; used: number; limit: number };

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
 * Self-service só (`BookingSource.self`) — atribuição manual por
 * Instrutor/Gestor é Fase 5+/6 (`booking.dart`); por isso usa
 * `requireAuthenticated`, não `requireManager`, mas ainda assim
 * verifica `memberId === caller.uid` como defesa em profundidade (o
 * parâmetro existe porque o repository Dart já o passava desde a
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

  // Elegibilidade (Fase 3) + regra de utilização aplicável (Fase 4):
  // lidas ANTES da transação, mesmo raciocínio de `BookSessionUseCase`
  // — não é uma corrida de concorrência entre membros diferentes (cada
  // um só lê a SUA subscription). A janela entre esta leitura e o
  // commit da transação é a mesma aceite hoje para a elegibilidade: um
  // Gestor mudar a UsageRule do Plan neste intervalo exato é uma
  // corrida teórica, não algo que valha a pena pagar o custo de mover
  // para dentro da transação.
  const subscriptionsSnap = await tenantRef
    .collection('subscriptions')
    .where('memberId', '==', memberId)
    .where('status', '==', 'active')
    .where('activeServiceIds', 'array-contains', serviceId)
    .limit(1)
    .get();
  if (subscriptionsSnap.empty) {
    throw new HttpsError(
      'permission-denied',
      'Não tens um plano ativo que dê acesso a este serviço.',
    );
  }
  const planId = subscriptionsSnap.docs[0].data().planId as string;

  const planServiceSnap = await tenantRef
    .collection('plans')
    .doc(planId)
    .collection('services')
    .doc(serviceId)
    .get();
  const usageRule = planServiceSnap.exists
    ? (planServiceSnap.data()!.usage as { type?: string; limit?: number })
    : { type: 'unlimited' };
  const isLimited = usageRule?.type === 'limited';
  const limit = usageRule?.limit;

  const period = isoWeekKey(startAt);
  const { start: periodStart, end: periodEnd } = isoWeekRange(startAt);
  const usageRef = tenantRef.collection('usage').doc(`${memberId}_${serviceId}_${period}`);

  const result = await firestore.runTransaction<TxResult>(async (tx) => {
    // Todas as leituras antes de qualquer escrita (regra do Firestore).
    const occSnap = await tx.get(occurrenceRef);
    const bookingSnap = await tx.get(bookingRef);
    const usageSnap = isLimited ? await tx.get(usageRef) : null;

    if (!occSnap.exists) return { kind: 'not-found' };
    const occData = occSnap.data()!;
    if (((occData.status as string) ?? 'scheduled') !== 'scheduled') {
      return { kind: 'not-found' };
    }
    const capacity = occData.capacity as number;
    const activeCount = (occData.activeBookingCount as number | undefined) ?? 0;

    if (bookingSnap.exists && bookingSnap.data()?.status === 'booked') {
      return { kind: 'already-booked' };
    }
    if (activeCount >= capacity) {
      return { kind: 'capacity' };
    }

    // Fase 4 story 5: `isExtra` nunca é true num booking self-service —
    // só faria sentido numa atribuição manual (Instrutor/Gestor,
    // Fase 5+/6), que ainda não tem nenhuma UI/endpoint. A lógica de
    // consumo já respeita a flag (o `if (!isExtra)` abaixo), pronta
    // para quando essa atribuição manual existir — não falta reescrever
    // isto, só ligar um caminho novo que a defina como `true`.
    const isExtra = false;
    let usedBefore = 0;
    if (isLimited && !isExtra) {
      usedBefore = (usageSnap?.data()?.used as number | undefined) ?? 0;
      if (limit !== undefined && usedBefore >= limit) {
        return { kind: 'usage-limit', used: usedBefore, limit };
      }
    }

    tx.set(bookingRef, {
      memberId,
      status: 'booked',
      source: 'self',
      isExtra,
      serviceId,
      period,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(occurrenceRef, { activeBookingCount: activeCount + 1 });

    if (isLimited && !isExtra) {
      tx.set(
        usageRef,
        {
          memberId,
          serviceId,
          period,
          periodType: 'week',
          periodStart: Timestamp.fromDate(periodStart),
          periodEnd: Timestamp.fromDate(periodEnd),
          used: usedBefore + 1,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    return { kind: 'booked' };
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
