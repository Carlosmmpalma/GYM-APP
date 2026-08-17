import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';

const inputSchema = z.object({
  weekId: z.string().min(1),
  slotId: z.string().min(1),
  memberIds: z.array(z.string().min(1)).min(1),
});

type MemberOutcome =
  | { memberId: string; ok: true }
  | { memberId: string; ok: false; reason: string };

/**
 * Fase 7 (UC08-A/UC17 fechado) — atribuição manual pelo Gestor a um
 * bloco de treino livre, mesmo espírito de `assignMembersToOccurrence.ts`
 * (mesma validação partilhada, `source: 'manager'`, um membro por vez
 * sem falhar o pedido inteiro). Ao contrário de `bookFreeTrainingSlot.ts`,
 * não valida se a semana está `published` — o Gestor pode pré-atribuir
 * alunos a uma sugestão ainda por aprovar, antes de a publicar.
 */
export const assignMembersToFreeTrainingSlot = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { weekId, slotId, memberIds } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const slotRef = tenantRef
    .collection('freeTrainingSchedules')
    .doc(weekId)
    .collection('slots')
    .doc(slotId);

  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Este horário já não está disponível.');
  }
  const slotData = slotSnap.data()!;
  const serviceId = slotData.serviceId as string;
  const startAt = (slotData.startAt as Timestamp).toDate();

  const results: MemberOutcome[] = [];
  for (const memberId of memberIds) {
    const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);
    if (!eligibility) {
      results.push({ memberId, ok: false, reason: 'not-eligible' });
      continue;
    }

    const result = await runBookingTransaction(firestore, {
      tenantRef,
      occurrenceRef: slotRef,
      bookingRef: slotRef.collection('bookings').doc(memberId),
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
