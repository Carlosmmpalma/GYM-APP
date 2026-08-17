import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberIds: z.array(z.string().min(1)).min(1),
  // UC08-A (fechado) — "+ Sessão extra" no mockup: isenta estes
  // membros do limite semanal do próprio plano (nunca da capacidade da
  // sala, que continua a aplicar-se sempre). `false` por omissão —
  // atribuição manual normal conta para o limite como qualquer
  // marcação (UC08 fechado).
  isExtra: z.boolean().optional().default(false),
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
 *
 * Fase 8 (auditoria funcional) — `requireManagerOrInstructor`, não
 * `requireManager`: esta função também serve o botão "+ Sessão extra"
 * (UC08-A) e "Adicionar membro" em `OccurrenceDetailScreen`, o mesmo
 * ecrã "Detalhe da aula" onde presença/reduzir vagas/cancelar/remarcar
 * já são Manager OU Instrutor desde a Fase 6 — nunca fazia sentido só
 * esta ação ficar mais restrita que as vizinhas na mesma tela.
 */
export const assignMembersToOccurrence = onCall(async (request) => {
  const caller = requireManagerOrInstructor(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { occurrenceId, memberIds, isExtra } = parsed.data;

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
      isExtra,
    });

    if (result.kind === 'booked') {
      results.push({ memberId, ok: true });
    } else {
      results.push({ memberId, ok: false, reason: result.kind });
    }
  }

  return { results };
});
