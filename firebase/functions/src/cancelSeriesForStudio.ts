import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { applyRelease, prepareRelease, ReleasePlan } from './lib/bookingLogic';
import { notifyMembers } from './lib/notifications';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  seriesId: z.string().min(1),
});

/**
 * Cancelar uma série, e as aulas futuras que ela gerou.
 *
 * ## Porque isto passou a existir
 *
 * `SessionSeriesRepository.cancelSeries` era uma escrita DIRETA do
 * cliente: um batch que punha `status: 'cancelled'` na série e em cada
 * ocorrência futura. Isso deixou de ser possível quando as Rules
 * passaram a exigir, no `update` de `sessionOccurrences`:
 *
 *     request.resource.data.status == resource.data.status
 *
 * A regra é deliberada e continua certa — cancelar tem de CASCATAR, e
 * só uma Cloud Function pode fazê-lo. O que ficou por fazer foi migrar
 * o `cancelSeries` junto com o `cancelOccurrence`, que foi migrado na
 * mesma altura (ver `cancelOccurrenceForStudio.ts`).
 *
 * O resultado era um `permission-denied` a um Gestor com todas as
 * permissões — e um batch é atómico, por isso nem a série chegava a ser
 * cancelada, apesar de as Rules permitirem essa parte.
 *
 * ## O que a escrita direta nunca fazia
 *
 * Mesmo que as Rules a deixassem passar, ela só mudava `status`. As
 * marcações dos alunos ficavam `booked` numa aula cancelada, e a
 * utilização semanal continuava consumida: o aluno perdia a sessão do
 * plano por causa de uma aula que o estúdio cancelou.
 *
 * Aqui, cada ocorrência futura liberta todas as marcações ativas
 * (devolvendo a utilização) antes de ser marcada como cancelada —
 * exatamente o que `cancelOccurrenceForStudio` faz para uma só.
 *
 * ## Uma transação por ocorrência, não uma para tudo
 *
 * Mesmo padrão de `deactivateInstructor`: oito semanas de uma série
 * semanal são oito ocorrências, cada uma com as suas marcações e
 * documentos de utilização. Numa transação só, um estúdio cheio passava
 * o limite de escritas — e uma falha a meio desfazia o trabalho todo.
 *
 * Assim, uma falha na quinta deixa as quatro primeiras canceladas. Não
 * é atómico, e é dito: o ecrã recebe a contagem do que ficou feito.
 */
export const cancelSeriesForStudio =
    onCall({ timeoutSeconds: 120 }, async (request) => {
  const caller = requireManagerOrInstructor(request);

  const { seriesId } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const seriesRef = tenantRef.collection('sessionSeries').doc(seriesId);

  const seriesSnap = await seriesRef.get();
  if (!seriesSnap.exists) {
    throw new HttpsError('not-found', 'Esta série já não existe.');
  }

  // A série primeiro: a partir daqui o cron já não gera ocorrências
  // novas, mesmo que a cascata abaixo demore ou falhe a meio.
  await seriesRef.update({ status: 'cancelled' });

  const occurrencesSnap = await tenantRef
    .collection('sessionOccurrences')
    .where('seriesId', '==', seriesId)
    .where('startAt', '>=', new Date())
    .get();
  const agendadas = occurrencesSnap.docs.filter(
    (doc) => (doc.data().status as string | undefined) === 'scheduled',
  );

  let cancelledOccurrences = 0;
  let cancelledBookings = 0;
  const affectedMemberIds = new Set<string>();

  for (const occDoc of agendadas) {
    const occurrenceRef = occDoc.ref;
    const libertados = await firestore.runTransaction(async (tx) => {
      const activeBookingsSnap = await tx.get(
        occurrenceRef.collection('bookings').where('status', '==', 'booked'),
      );
      const plans: ReleasePlan[] = [];
      for (const bookingDoc of activeBookingsSnap.docs) {
        const plan = await prepareRelease(tx, {
          tenantRef,
          occurrenceRef,
          memberId: bookingDoc.id,
        });
        if (plan) plans.push(plan);
      }
      for (const plan of plans) {
        applyRelease(tx, plan);
      }
      tx.update(occurrenceRef, { status: 'cancelled', activeBookingCount: 0 });
      return plans.map((p) => p.memberId);
    });

    cancelledOccurrences += 1;
    cancelledBookings += libertados.length;
    for (const memberId of libertados) affectedMemberIds.add(memberId);
  }

  // UMA notificação por aluno, não uma por aula cancelada: quem tinha as
  // oito semanas marcadas receberia oito avisos iguais. Mesmo raciocínio
  // de `deactivateInstructor`.
  if (affectedMemberIds.size > 0) {
    await notifyMembers(
      tenantRef,
      [...affectedMemberIds],
      'Aulas canceladas',
      'Estas aulas deixaram de se repetir. As tuas marcações futuras '
        + 'foram canceladas e voltaram ao teu limite semanal.',
    );
  }

  return { cancelledOccurrences, cancelledBookings };
});
