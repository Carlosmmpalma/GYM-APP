import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { resolveEligibility } from './lib/bookingLogic';
import { renumberWaitlist } from './lib/waitlist';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberId: z.string().min(1),
});

/**
 * Fase 11 — entrar na lista de espera de uma sessão cheia.
 *
 * Cloud Function e não escrita direta pela mesma razão de
 * `createBooking`: é preciso ler a ocorrência e as subscrições do membro
 * para decidir, e nada disso pode ser decidido pelo cliente.
 *
 * Recusa em três casos, e cada um é uma mensagem diferente:
 *  - a sessão AINDA tem vagas → devia marcar, não esperar;
 *  - já tem marcação nesta sessão → não faz sentido esperar por si
 *    próprio;
 *  - não tem plano que dê acesso ao serviço → entrar na fila seria
 *    prometer um lugar que nunca poderia ocupar.
 */
export const joinWaitlist = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'joinWaitlist',
    maxCalls: 30,
    windowSeconds: 60,
  });

  const { occurrenceId, memberId } = parseInput(inputSchema, request.data);

  // Um membro só entra na fila por si; Instrutor e Gestor podem pôr
  // alguém, que é o caso do balcão ("põe-me na lista para quinta").
  const isSelf = memberId === caller.uid;
  const isStaff =
    caller.roles.includes('manager') || caller.roles.includes('instructor');
  if (!isSelf && !isStaff) {
    throw new HttpsError(
      'permission-denied',
      'Só podes entrar na lista de espera por ti.',
    );
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef
    .collection('sessionOccurrences')
    .doc(occurrenceId);

  const occurrenceSnap = await occurrenceRef.get();
  if (!occurrenceSnap.exists) {
    throw new HttpsError('not-found', 'Sessão não encontrada.');
  }
  if ((occurrenceSnap.get('status') as string) !== 'scheduled') {
    throw new HttpsError(
      'failed-precondition',
      'Esta sessão já não está agendada.',
    );
  }

  const capacity = (occurrenceSnap.get('capacity') as number) ?? 0;
  const active = (occurrenceSnap.get('activeBookingCount') as number) ?? 0;
  if (active < capacity) {
    throw new HttpsError('failed-precondition', 'Esta sessão ainda tem vagas.', {
      reason: 'has-capacity',
    });
  }

  const bookingSnap = await occurrenceRef
    .collection('bookings')
    .doc(memberId)
    .get();
  if (bookingSnap.exists && bookingSnap.get('status') === 'booked') {
    throw new HttpsError(
      'already-exists',
      'Já tens marcação nesta sessão.',
      { reason: 'already-booked' },
    );
  }

  const serviceId = occurrenceSnap.get('serviceId') as string;
  const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);
  if (!eligibility) {
    throw new HttpsError(
      'failed-precondition',
      'Não tens um plano ativo que dê acesso a este serviço.',
      { reason: 'not-eligible' },
    );
  }

  // `merge: false` com o memberId como id do documento: entrar duas
  // vezes é impossível, e uma segunda tentativa não avança na fila.
  const entryRef = occurrenceRef.collection('waitlist').doc(memberId);
  if ((await entryRef.get()).exists) {
    return { alreadyInQueue: true };
  }

  await entryRef.set({
    memberId,
    joinedAt: FieldValue.serverTimestamp(),
    addedBy: caller.uid,
  });
  await renumberWaitlist(occurrenceRef);

  return { alreadyInQueue: false };
});

/** Sair da lista de espera. */
export const leaveWaitlist = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  const { occurrenceId, memberId } = parseInput(inputSchema, request.data);

  const isSelf = memberId === caller.uid;
  const isStaff =
    caller.roles.includes('manager') || caller.roles.includes('instructor');
  if (!isSelf && !isStaff) {
    throw new HttpsError(
      'permission-denied',
      'Só podes sair da lista de espera por ti.',
    );
  }

  const occurrenceRef = getFirestore()
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('sessionOccurrences')
    .doc(occurrenceId);
  await occurrenceRef.collection('waitlist').doc(memberId).delete();
  await renumberWaitlist(occurrenceRef);

  return { left: true };
});
