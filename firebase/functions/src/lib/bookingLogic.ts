import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { isoWeekKey, isoWeekRange } from './isoWeek';

export type BookingTxResult =
  | { kind: 'booked' }
  | { kind: 'already-booked' }
  | { kind: 'capacity' }
  | { kind: 'not-found' }
  | { kind: 'usage-limit'; used: number; limit: number };

export interface EligibilityInfo {
  planId: string;
  isLimited: boolean;
  limit?: number;
}

/**
 * Fase 5 — extraído de `createBooking.ts` para ser partilhado por
 * `generateRecurringOccurrences.ts` (auto-atribuição de membros
 * pré-atribuídos numa série) e `assignMembersToOccurrence.ts`
 * (atribuição manual pelo Gestor). Duplicar esta lógica em três
 * ficheiros arriscaria as regras de negócio divergirem entre o
 * caminho self-service e os caminhos de atribuição manual — o próprio
 * Firestore Data Model v1 §52 pede autoridade única no backend para
 * elegibilidade/limite semanal.
 *
 * Domain Model v1 §14/15 — resolve se `memberId` tem uma subscription
 * ativa que dá acesso a `serviceId`, e qual a UsageRule aplicável a essa
 * combinação Plan+Service. Lido FORA de qualquer transação (mesmo
 * raciocínio já aceite desde a Fase 4: não é uma corrida de
 * concorrência entre membros diferentes, cada um só lê a SUA
 * subscription). `null` quando o membro não tem nenhuma subscription
 * ativa que dê acesso a este serviço.
 */
export async function resolveEligibility(
  tenantRef: FirebaseFirestore.DocumentReference,
  memberId: string,
  serviceId: string,
): Promise<EligibilityInfo | null> {
  const subscriptionsSnap = await tenantRef
    .collection('subscriptions')
    .where('memberId', '==', memberId)
    .where('status', '==', 'active')
    .where('activeServiceIds', 'array-contains', serviceId)
    .limit(1)
    .get();
  if (subscriptionsSnap.empty) return null;
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

  return { planId, isLimited, limit };
}

/**
 * Firestore Data Model v1 §29-30 — a transação que garante que a
 * capacidade nunca é ultrapassada mesmo sob concorrência real (Fase 2),
 * validando também o limite semanal de utilização (Fase 4). `source`
 * distingue quem originou a reserva (Domain Model v1 §24) — o
 * comportamento para `source: 'self'` é byte-a-byte o mesmo que
 * `createBooking.ts` tinha antes deste refactor.
 */
export async function runBookingTransaction(
  firestore: FirebaseFirestore.Firestore,
  params: {
    tenantRef: FirebaseFirestore.DocumentReference;
    occurrenceRef: FirebaseFirestore.DocumentReference;
    bookingRef: FirebaseFirestore.DocumentReference;
    memberId: string;
    serviceId: string;
    startAt: Date;
    source: 'self' | 'instructor' | 'manager';
    eligibility: EligibilityInfo;
    // UC08 (fechado) — "atribuição manual conta sempre para o limite
    // semanal, exceto UC08-A (sessão extra explícita)". `false` por
    // omissão para todos os caminhos existentes (self/manager) — só
    // `assignMembersToOccurrence.ts` (o único caminho que oferece
    // "+ Sessão extra" na UI) alguma vez passa `true`.
    isExtra?: boolean;
  },
): Promise<BookingTxResult> {
  const {
    tenantRef,
    occurrenceRef,
    bookingRef,
    memberId,
    serviceId,
    startAt,
    source,
    eligibility,
    isExtra = false,
  } = params;
  const { isLimited, limit } = eligibility;

  const period = isoWeekKey(startAt);
  const { start: periodStart, end: periodEnd } = isoWeekRange(startAt);
  const usageRef = tenantRef.collection('usage').doc(`${memberId}_${serviceId}_${period}`);

  return firestore.runTransaction<BookingTxResult>(async (tx) => {
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

    // UC08-A — uma sessão extra continua a exigir vaga na sala (o
    // `activeCount >= capacity` acima aplica-se sempre); só isenta o
    // membro do LIMITE SEMANAL do próprio plano, que é uma restrição
    // diferente e independente.
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
      source,
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
}

export interface ReleasePlan {
  memberId: string;
  bookingRef: FirebaseFirestore.DocumentReference;
  usageRef: FirebaseFirestore.DocumentReference | null;
  usageUsedBefore: number;
  /**
   * UC08-A — se a marcação libertada era uma sessão EXTRA. Exposto
   * porque `rescheduleBooking.ts` precisa de o REPLICAR na marcação de
   * destino: sem isto, remarcar uma sessão extra criava no destino uma
   * marcação normal, que passa a consumir o limite semanal — o membro
   * perdia uma utilização só porque o estúdio o mudou de horário.
   */
  isExtra: boolean;
}

/**
 * Fase 6 (UC18/UC10) — fase de LEITURA de "libertar um membro de uma
 * ocorrência, estúdio-iniciado" (reduzir vagas, cancelar sessão,
 * remarcar). Ao contrário de `cancelBooking.ts` (o membro a cancelar,
 * sujeito à janela de antecedência mínima), isto devolve usage SEMPRE
 * — não é o membro que está a desistir tarde, é o estúdio a decidir.
 *
 * Separado em leitura ([prepareRelease]) e escrita ([applyRelease])
 * de propósito: quando se liberta MAIS do que um membro na mesma
 * transação (`removeMembersFromOccurrence`/`cancelOccurrenceForStudio`),
 * o Firestore exige que TODAS as leituras de uma transação aconteçam
 * antes de QUALQUER escrita — chamar uma função "leitura+escrita" num
 * `for` violaria isso a partir do segundo membro. `null` quando não há
 * nada para libertar (já não estava `booked`).
 */
export async function prepareRelease(
  tx: FirebaseFirestore.Transaction,
  params: {
    tenantRef: FirebaseFirestore.DocumentReference;
    occurrenceRef: FirebaseFirestore.DocumentReference;
    memberId: string;
  },
): Promise<ReleasePlan | null> {
  const bookingRef = params.occurrenceRef.collection('bookings').doc(params.memberId);
  const bookingSnap = await tx.get(bookingRef);
  if (!bookingSnap.exists || bookingSnap.data()?.status !== 'booked') {
    return null;
  }
  const bookingData = bookingSnap.data()!;
  const serviceId = bookingData.serviceId as string | undefined;
  const period = bookingData.period as string | undefined;
  // UC08-A — uma sessão EXTRA nunca incrementou `usage` (ver
  // `runBookingTransaction` acima: o `tx.set(usageRef, ...)` é
  // `if (isLimited && !isExtra)`), por isso libertá-la também não pode
  // decrementar. Sem esta verificação, cancelar uma sessão extra
  // roubava uma utilização que o membro nunca tinha gasto — ficava com
  // 0/2 depois de ter usado 1 sessão normal. Bug real, apanhado na
  // varredura da Fase 8 ao tornar `isExtra` funcional (até aí era
  // sempre `false`, e por isso este caminho nunca podia estar errado).
  const isExtra = (bookingData.isExtra as boolean | undefined) ?? false;
  const usageRef =
    serviceId && period && !isExtra
      ? params.tenantRef.collection('usage').doc(`${params.memberId}_${serviceId}_${period}`)
      : null;
  const usageSnap = usageRef ? await tx.get(usageRef) : null;

  return {
    memberId: params.memberId,
    bookingRef,
    usageRef: usageSnap?.exists ? usageRef : null,
    usageUsedBefore: (usageSnap?.data()?.used as number | undefined) ?? 0,
    isExtra,
  };
}

/** Fase de ESCRITA correspondente a [prepareRelease] — nenhuma leitura aqui. */
export function applyRelease(tx: FirebaseFirestore.Transaction, plan: ReleasePlan): void {
  tx.update(plan.bookingRef, {
    status: 'cancelled',
    cancelledAt: FieldValue.serverTimestamp(),
  });
  if (plan.usageRef) {
    tx.update(plan.usageRef, {
      used: plan.usageUsedBefore > 0 ? plan.usageUsedBefore - 1 : 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}
