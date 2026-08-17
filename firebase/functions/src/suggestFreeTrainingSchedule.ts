import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { weekIdForDate } from './lib/isoWeek';

const inputSchema = z.object({
  // Qualquer data dentro da semana pretendida — normalizado
  // server-side para a segunda-feira dessa semana ISO (`weekIdForDate`).
  weekStart: z.string().min(1),
  serviceId: z.string().min(1),
});

/**
 * Fase 7 (UC17-A fechado) — "o sistema deve SUGERIR a grelha da semana
 * seguinte com base na grelha da semana anterior, mas nunca aplicá-la
 * sozinho". Chamada quando o Gestor abre `ManageFreeTrainingScreen`
 * para uma semana que ainda não tem `freeTrainingSchedules/{weekId}` —
 * idempotente por id determinístico (`weekId`), mesmo padrão de
 * `generateRecurringOccurrences.ts`: se já existir QUALQUER coisa para
 * esta semana (rascunho, sugestão já editada, ou já publicada), nunca
 * é substituída às cegas.
 *
 * Sem semana anterior com horários (`slots` vazio ou nunca existiu) →
 * nasce `draft` (grelha vazia, o Gestor começa do zero) — não faz
 * sentido chamar de "sugestão" algo que não copiou nada. Com semana
 * anterior → copia cada slot (mesma hora do dia, mesma capacidade,
 * `activeBookingCount` sempre a 0 — nunca copia reservas) desviado
 * exatamente 7 dias, nasce `suggested`.
 */
export const suggestFreeTrainingSchedule = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { weekStart, serviceId } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const weekId = weekIdForDate(new Date(weekStart));
  const scheduleRef = tenantRef.collection('freeTrainingSchedules').doc(weekId);

  const existing = await scheduleRef.get();
  if (existing.exists) {
    return { weekId, status: existing.data()!.status as string, created: false };
  }

  const previousMonday = new Date(`${weekId}T00:00:00.000Z`);
  previousMonday.setUTCDate(previousMonday.getUTCDate() - 7);
  const previousWeekId = weekIdForDate(previousMonday);
  const previousSlotsSnap = await tenantRef
    .collection('freeTrainingSchedules')
    .doc(previousWeekId)
    .collection('slots')
    .get();

  const status = previousSlotsSnap.empty ? 'draft' : 'suggested';
  const batch = firestore.batch();
  batch.set(scheduleRef, {
    weekStart: Timestamp.fromDate(new Date(`${weekId}T00:00:00.000Z`)),
    status,
    serviceId,
    createdBy: caller.uid,
    createdAt: FieldValue.serverTimestamp(),
  });

  for (const slotDoc of previousSlotsSnap.docs) {
    const data = slotDoc.data();
    const prevStart = (data.startAt as Timestamp).toDate();
    const prevEnd = (data.endAt as Timestamp).toDate();
    const shiftMs = 7 * 24 * 60 * 60 * 1000;
    batch.set(scheduleRef.collection('slots').doc(), {
      serviceId: (data.serviceId as string | undefined) ?? serviceId,
      startAt: Timestamp.fromDate(new Date(prevStart.getTime() + shiftMs)),
      endAt: Timestamp.fromDate(new Date(prevEnd.getTime() + shiftMs)),
      capacity: data.capacity as number,
      activeBookingCount: 0,
    });
  }

  await batch.commit();
  return { weekId, status, created: true, slotsCopied: previousSlotsSnap.size };
});
