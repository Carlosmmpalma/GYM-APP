import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import {
  applyRelease,
  prepareRelease,
  resolveEligibility,
  runBookingTransaction,
} from './lib/bookingLogic';

const inputSchema = z.object({
  fromOccurrenceId: z.string().min(1),
  toOccurrenceId: z.string().min(1),
  memberId: z.string().min(1),
});

/**
 * Fase 6 (UC10-B) — "remarcar aluno": cancela a marcação na ocorrência
 * de origem (vaga + usage sempre devolvida, `prepareRelease`/
 * `applyRelease` — mesma lógica estúdio-iniciada de
 * `removeMembersFromOccurrence.ts`) e tenta marcar na ocorrência de
 * destino (`resolveEligibility`+`runBookingTransaction`, `source:
 * manager`). Manager OU Instrutor.
 *
 * **Não é atómico entre origem e destino** — são duas ocorrências
 * (dois documentos + subcoleções) diferentes, e o Firestore não dá
 * para juntar isso numa única transação de forma que valha a pena.
 * Se o passo 2 falhar (sessão de destino cheia, sem elegibilidade), a
 * origem JÁ FOI cancelada — a função devolve um erro com `reason`
 * prefixado `from-cancelled-` precisamente para a UI conseguir
 * mostrar isto com clareza, em vez de sugerir que nada aconteceu.
 * Mesmo espírito de `assignMembersToOccurrence.ts`: melhor um
 * resultado parcial claro do que fingir atomicidade que não existe.
 */
export const rescheduleBooking = onCall(async (request) => {
  const caller = requireManagerOrInstructor(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { fromOccurrenceId, toOccurrenceId, memberId } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const fromRef = tenantRef.collection('sessionOccurrences').doc(fromOccurrenceId);
  const toRef = tenantRef.collection('sessionOccurrences').doc(toOccurrenceId);

  // Passo 1 — liberta a marcação de origem.
  const released = await firestore.runTransaction(async (tx) => {
    const occSnap = await tx.get(fromRef);
    const plan = await prepareRelease(tx, { tenantRef, occurrenceRef: fromRef, memberId });
    if (!plan) return false;

    applyRelease(tx, plan);
    const activeCount = (occSnap.data()?.activeBookingCount as number | undefined) ?? 0;
    tx.update(fromRef, { activeBookingCount: Math.max(0, activeCount - 1) });
    return true;
  });

  if (!released) {
    throw new HttpsError(
      'not-found',
      'Este membro não tem uma marcação ativa na sessão de origem.',
    );
  }

  // Passo 2 — tenta marcar no destino. A origem já está cancelada a
  // partir daqui, independentemente do que acontecer a seguir.
  const toSnap = await toRef.get();
  if (!toSnap.exists) {
    throw new HttpsError(
      'not-found',
      'A sessão de origem foi cancelada, mas a sessão de destino já não ' +
        'está disponível — o membro ficou sem marcação. Marca-o manualmente.',
      { reason: 'from-cancelled-to-not-found' },
    );
  }
  const toData = toSnap.data()!;
  const serviceId = toData.serviceId as string;
  const startAt = (toData.startAt as Timestamp).toDate();

  const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);
  if (!eligibility) {
    throw new HttpsError(
      'permission-denied',
      'A sessão de origem foi cancelada, mas o membro não tem um plano ' +
        'ativo que dê acesso ao serviço da sessão de destino.',
      { reason: 'from-cancelled-not-eligible' },
    );
  }

  const bookingRef = toRef.collection('bookings').doc(memberId);
  const result = await runBookingTransaction(firestore, {
    tenantRef,
    occurrenceRef: toRef,
    bookingRef,
    memberId,
    serviceId,
    startAt,
    source: 'manager',
    eligibility,
  });

  if (result.kind !== 'booked') {
    throw new HttpsError(
      'resource-exhausted',
      'A sessão de origem foi cancelada, mas não foi possível marcar no ' +
        'destino (sem vaga ou já marcado lá). Marca o membro manualmente.',
      { reason: `from-cancelled-${result.kind}` },
    );
  }

  return { rescheduled: true };
});
