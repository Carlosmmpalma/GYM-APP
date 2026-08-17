import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';

const inputSchema = z.object({
  weekId: z.string().min(1),
});

/**
 * Fase 7 (UC17-A fechado) — "só depois de aprovada é que a grelha fica
 * visível para os alunos". Único caminho que muda `status` para
 * `published` — Cloud Function (Firestore Data Model v1 §53 já lista
 * `publishFreeTrainingSchedule` explicitamente como operação de
 * servidor), mesmo sem nenhuma invariante cross-documento a proteger
 * (é só um `status` a mudar): mantém a mesma barreira que
 * `sessionOccurrences.status` já tem desde a Fase 6 — nunca uma
 * escrita direta do cliente para mudar o que o Aluno vê.
 *
 * Idempotente: publicar uma semana já publicada não é erro.
 */
export const publishFreeTrainingSchedule = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { weekId } = parsed.data;

  const firestore = getFirestore();
  const scheduleRef = firestore
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('freeTrainingSchedules')
    .doc(weekId);

  const snap = await scheduleRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Esta semana ainda não tem nenhuma grelha.');
  }
  if (snap.data()!.status === 'published') {
    return { published: true };
  }

  const slotsSnap = await scheduleRef.collection('slots').limit(1).get();
  if (slotsSnap.empty) {
    throw new HttpsError(
      'failed-precondition',
      'Esta semana precisa de pelo menos um horário antes de publicar.',
    );
  }

  await scheduleRef.update({
    status: 'published',
    publishedAt: FieldValue.serverTimestamp(),
  });

  return { published: true };
});
