import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberIds: z.array(z.string().min(1)).min(1),
});

type MemberOutcome =
  | { memberId: string; ok: true }
  | { memberId: string; ok: false; reason: string };

/**
 * Fase 5 (UC17/UC19, UC08-A fechado) — atribuição manual pelo Gestor a
 * uma ocorrência concreta: criar uma sessão "só esta data" já com
 * alunos pré-atribuídos, ou acrescentar alguém a uma ocorrência já
 * gerada por uma série (`SeriesDetailScreen`). Mesma validação de
 * elegibilidade/capacidade/limite semanal de um booking normal
 * (`lib/bookingLogic.ts`, partilhado com `createBooking.ts` e
 * `generateRecurringOccurrences.ts`), só com `source: 'manager'` — e
 * SEM o requisito `memberId === caller.uid` de `createBooking.ts`, já
 * que aqui é sempre o Gestor a atribuir outra pessoa.
 *
 * Um membro por vez, nunca falha o pedido inteiro por causa de um só:
 * o resultado é devolvido por membro (mesmo espírito do resumo
 * devolvido por `generateRecurringOccurrencesNow`), para a UI poder
 * mostrar "3 atribuídos, 1 sem vaga, 1 sem plano ativo" em vez de um
 * erro genérico.
 */
export const assignMembersToOccurrence = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { occurrenceId, memberIds } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef.collection('sessionOccurrences').doc(occurrenceId);

  const occurrenceSnap = await occurrenceRef.get();
  if (!occurrenceSnap.exists) {
    throw new HttpsError('not-found', 'Esta sessão já não está disponível.');
  }
  const occurrenceData = occurrenceSnap.data()!;
  const serviceId = occurrenceData.serviceId as string;
  const startAt = (occurrenceData.startAt as Timestamp).toDate();

  const results: MemberOutcome[] = [];
  for (const memberId of memberIds) {
    const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);
    if (!eligibility) {
      results.push({ memberId, ok: false, reason: 'not-eligible' });
      continue;
    }

    const result = await runBookingTransaction(firestore, {
      tenantRef,
      occurrenceRef,
      bookingRef: occurrenceRef.collection('bookings').doc(memberId),
      memberId,
      serviceId,
      startAt,
      source: 'manager',
      eligibility,
    });

    if (result.kind === 'booked') {
      results.push({ memberId, ok: true });
    } else {
      results.push({ memberId, ok: false, reason: result.kind });
    }
  }

  return { results };
});
