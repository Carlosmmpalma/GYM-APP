import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';

const inputSchema = z.object({
  title: z.string().min(1),
  body: z.string().min(1),
  memberId: z.string().min(1).optional(),
  occurrenceId: z.string().min(1).optional(),
}).refine((data) => Boolean(data.memberId) !== Boolean(data.occurrenceId), {
  message: 'Indica exatamente um destino: memberId OU occurrenceId.',
});

/**
 * Fase 6 (UC21) — "notificar alunos": não existe nenhum conceito de
 * "alunos do instrutor" independente de uma sessão concreta (Domain
 * Model v1 não modela isso), por isso o alvo "todos os alunos" do
 * mockup simplifica para "todos os inscritos ativos numa sessão
 * concreta" quando se passa `occurrenceId` — sinalizado, não escondido.
 * `memberId` cobre o caso "um aluno específico".
 *
 * Precisa de Admin SDK só para ler `fcmTokens` de outros
 * membros/bookings (Security Rules dão leitura ampla no tenant, mas
 * não vale a pena ter um caminho client-side só para isto) e para
 * `admin.messaging()`, que não tem equivalente client-side.
 */
export const sendNotification = onCall(async (request) => {
  const caller = requireManagerOrInstructor(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { title, body, memberId, occurrenceId } = parsed.data;

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  let targetMemberIds: string[];
  if (memberId) {
    targetMemberIds = [memberId];
  } else {
    const bookingsSnap = await tenantRef
      .collection('sessionOccurrences')
      .doc(occurrenceId as string)
      .collection('bookings')
      .where('status', '==', 'booked')
      .get();
    targetMemberIds = bookingsSnap.docs.map((doc) => doc.id);
  }

  if (targetMemberIds.length === 0) {
    return { sent: 0, targets: 0 };
  }

  const memberDocs = await firestore.getAll(
    ...targetMemberIds.map((id) => tenantRef.collection('members').doc(id)),
  );
  const tokens = memberDocs
    .flatMap((doc) => (doc.data()?.fcmTokens as string[] | undefined) ?? [])
    .filter((token, index, all) => all.indexOf(token) === index);

  if (tokens.length === 0) {
    return { sent: 0, targets: targetMemberIds.length };
  }

  const result = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
  });

  return { sent: result.successCount, targets: targetMemberIds.length };
});
