import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { parseInput } from './lib/validation';
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
 *
 * O que se pode fazer, e passou a fazer-se, é **validar o destino
 * ANTES de largar a origem**. Antes, remarcar para uma sessão cheia,
 * cancelada, inexistente, ou para um serviço que o plano do aluno não
 * cobre, cancelava-lhe a marcação e deixava-o sem nada — o instrutor
 * carregava num botão para mudar alguém de hora e o aluno saía do
 * horário. Agora esses casos recusam antes de tocar em nada, e o
 * aluno fica exatamente onde estava.
 *
 * A janela que sobra é uma corrida real e estreita: alguém ocupar a
 * última vaga do destino entre a validação e a marcação. Nesse caso o
 * erro continua a vir com `reason` prefixado `from-cancelled-`, para a
 * UI dizer com clareza que a origem já não existe — melhor um
 * resultado parcial explícito do que fingir atomicidade que não há.
 *
 * A ordem contrária (marcar no destino primeiro, largar a origem
 * depois) eliminaria a corrida, mas parte quem tem limite semanal: o
 * aluno passaria a ocupar duas utilizações ao mesmo tempo e uma
 * remarcação neutra seria recusada por limite atingido.
 */
export const rescheduleBooking = onCall(async (request) => {
  const caller = requireManagerOrInstructor(request);

  const { fromOccurrenceId, toOccurrenceId, memberId } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const fromRef = tenantRef.collection('sessionOccurrences').doc(fromOccurrenceId);
  const toRef = tenantRef.collection('sessionOccurrences').doc(toOccurrenceId);

  // Passo 0 — o destino aguenta esta remarcação?
  //
  // Tudo o que se pode saber antes de mexer em nada é verificado
  // aqui. Não substitui as validações da transação de marcação (a
  // capacidade é reavaliada lá dentro, que é onde a corrida se
  // resolve); serve para que uma remarcação impossível não comece
  // sequer por cancelar o que o aluno já tinha.
  const toSnapBefore = await toRef.get();
  if (!toSnapBefore.exists) {
    throw new HttpsError('not-found', 'A sessão de destino não existe.');
  }
  if ((toSnapBefore.get('status') as string) !== 'scheduled') {
    throw new HttpsError(
      'failed-precondition',
      'A sessão de destino já não está agendada.',
      { reason: 'to-not-scheduled' },
    );
  }
  if (toOccurrenceId === fromOccurrenceId) {
    throw new HttpsError(
      'invalid-argument',
      'A sessão de destino é a mesma que a de origem.',
    );
  }

  const existingAtDestination = await toRef
    .collection('bookings')
    .doc(memberId)
    .get();
  if (
    existingAtDestination.exists &&
    existingAtDestination.get('status') === 'booked'
  ) {
    throw new HttpsError(
      'already-exists',
      'Este membro já tem marcação na sessão de destino.',
      { reason: 'to-already-booked' },
    );
  }

  const destinationServiceId = toSnapBefore.get('serviceId') as string;
  const destinationEligibility = await resolveEligibility(
    tenantRef,
    memberId,
    destinationServiceId,
  );
  if (!destinationEligibility) {
    throw new HttpsError(
      'permission-denied',
      'O plano deste membro não dá acesso ao serviço da sessão de destino.',
      { reason: 'to-not-eligible' },
    );
  }

  // A capacidade é verificada aqui só para recusar cedo o caso óbvio;
  // quem decide de facto é a transação, e é lá que a última vaga se
  // resolve entre pedidos simultâneos.
  const destinationCapacity = (toSnapBefore.get('capacity') as number) ?? 0;
  const destinationActive =
    (toSnapBefore.get('activeBookingCount') as number) ?? 0;
  if (destinationActive >= destinationCapacity) {
    throw new HttpsError(
      'resource-exhausted',
      'A sessão de destino não tem vagas.',
      { reason: 'to-capacity' },
    );
  }

  // Passo 1 — liberta a marcação de origem. `wasExtra` viaja daqui
  // para o passo 2: UC08-A, remarcar uma sessão extra tem de manter-se
  // extra no destino (ver `ReleasePlan.isExtra`).
  const released = await firestore.runTransaction(async (tx) => {
    const occSnap = await tx.get(fromRef);
    const plan = await prepareRelease(tx, { tenantRef, occurrenceRef: fromRef, memberId });
    if (!plan) return null;

    applyRelease(tx, plan);
    const activeCount = (occSnap.data()?.activeBookingCount as number | undefined) ?? 0;
    tx.update(fromRef, { activeBookingCount: Math.max(0, activeCount - 1) });
    return { isExtra: plan.isExtra };
  });

  if (!released) {
    throw new HttpsError(
      'not-found',
      'Este membro não tem uma marcação ativa na sessão de origem.',
    );
  }

  // Passo 2 — marca no destino. A origem já está cancelada a partir
  // daqui; o que o passo 0 garantiu é que só uma corrida pela última
  // vaga pode fazer isto falhar.
  const serviceId = destinationServiceId;
  const startAt = (toSnapBefore.get('startAt') as Timestamp).toDate();
  const eligibility = destinationEligibility;

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
    isExtra: released.isExtra,
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
