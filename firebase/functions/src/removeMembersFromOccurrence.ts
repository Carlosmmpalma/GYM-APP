import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { applyRelease, prepareRelease, ReleasePlan } from './lib/bookingLogic';
import { describeOccurrence, notifyMembers } from './lib/notifications';
import { promoteFromWaitlist } from './lib/waitlist';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberIds: z.array(z.string().min(1)).min(1),
  // UC18 (atualizado) — opcional: reduzir vagas também baixa a
  // capacidade, além de remover quem foi escolhido. Sem isto (ex.:
  // um Gestor só quer libertar alguém sem baixar o limite), a
  // capacidade fica como estava.
  newCapacity: z.number().int().positive().optional(),
});

/**
 * Fase 6 (UC18 atualizado) — "reduzir vagas com seleção explícita de
 * quem remover". Cada `memberId` é libertado da ocorrência (vaga
 * liberta + usage SEMPRE devolvida — decisão estúdio-iniciada, não
 * sujeita à janela de antecedência mínima de `cancelBooking.ts`).
 * Manager OU Instrutor (mockup mostra "Reduzir vagas" na secção
 * Instrutor).
 */
export const removeMembersFromOccurrence = onCall(async (request) => {
  const caller = requireManagerOrInstructor(request);

  const { occurrenceId, memberIds, newCapacity } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef.collection('sessionOccurrences').doc(occurrenceId);

  const result = await firestore.runTransaction(async (tx) => {
    const occSnap = await tx.get(occurrenceRef);
    if (!occSnap.exists) {
      throw new HttpsError('not-found', 'Esta sessão já não está disponível.');
    }

    // Fase de leitura — todos os `prepareRelease` antes de qualquer
    // escrita (ver nota em `lib/bookingLogic.ts`).
    const plans: ReleasePlan[] = [];
    for (const memberId of memberIds) {
      const plan = await prepareRelease(tx, { tenantRef, occurrenceRef, memberId });
      if (plan) plans.push(plan);
    }

    // Fase de escrita.
    for (const plan of plans) {
      applyRelease(tx, plan);
    }
    const activeCount = (occSnap.data()?.activeBookingCount as number | undefined) ?? 0;
    tx.update(occurrenceRef, {
      activeBookingCount: Math.max(0, activeCount - plans.length),
      ...(newCapacity !== undefined ? { capacity: newCapacity } : {}),
    });

    return {
      removed: plans.map((p) => p.memberId),
      startAt: (occSnap.data()?.startAt as Timestamp | undefined)?.toDate(),
    };
  });

  // UC18 (fechado) — "os alunos removidos são notificados (UC11)".
  // FORA da transação, e sem `await` a bloquear o resultado em caso de
  // erro: o `notifyMembers` nunca lança (ver `lib/notifications.ts`),
  // mas mesmo assim a remoção já está confirmada neste ponto.
  if (result.removed.length > 0) {
    const when = result.startAt ? describeOccurrence(result.startAt) : 'uma sessão marcada';
    await notifyMembers(
      tenantRef,
      result.removed,
      'Marcação cancelada pelo estúdio',
      `A tua marcação de ${when} foi cancelada. A sessão volta ao teu limite semanal.`,
    );
  }

  // Tirar alguém de uma sessão liberta um lugar — e havia quem
  // estivesse à espera dele. `promoteFromWaitlist` só promove se
  // houver espaço de facto, por isso é seguro chamar também quando
  // isto veio de "reduzir vagas" (aí a lotação desceu com as
  // remoções e não sobra nada para promover).
  const promotion = await promoteFromWaitlist({
    tenantRef,
    occurrenceId,
    maxPromotions: result.removed.length,
  });

  return {
    removed: result.removed,
    promotedFromWaitlist: promotion.promotedMemberIds.length,
  };
});
