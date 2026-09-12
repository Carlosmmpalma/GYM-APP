import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { promoteFromWaitlist } from './lib/waitlist';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  memberId: z.string().min(1),
});

/**
 * Fase 4 — migra `cancelBooking` para Cloud Function, mesmo motivo de
 * `createBooking` nesta fase: precisa de ler `tenants/{t}/config/
 * bookingPolicy` (antecedência mínima) e, condicionalmente, devolver
 * `usage/{memberId}_{serviceId}_{period}`.
 *
 * Decisão (Carlos, ver README): cancelar SEMPRE liberta a vaga
 * (`activeBookingCount` desce), independentemente da janela — só a
 * devolução da UTILIZAÇÃO semanal depende de estar dentro da
 * antecedência mínima configurada. Fora da janela, cancela na mesma
 * mas a utilização fica consumida (penalização por cancelar tarde).
 */
export const cancelBooking = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  // mesmo raciocínio de createBooking — marcar/cancelar em ciclo
  // custa transações
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'cancelBooking',
    maxCalls: 30,
    windowSeconds: 60,
  });

  const { occurrenceId, memberId } = parseInput(inputSchema, request.data);

  if (memberId !== caller.uid) {
    throw new HttpsError(
      'permission-denied',
      'Só podes cancelar uma marcação tua.',
    );
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef.collection('sessionOccurrences').doc(occurrenceId);
  const bookingRef = occurrenceRef.collection('bookings').doc(memberId);

  // Lido fora da transação — é config de negócio, não algo que mude à
  // velocidade de uma corrida de concorrência (mesmo raciocínio já
  // aceite para a elegibilidade em `createBooking`).
  const policySnap = await tenantRef.collection('config').doc('bookingPolicy').get();
  const minNoticeHours =
    (policySnap.data()?.minCancellationNoticeHours as number | undefined) ?? 0;

  const result = await firestore.runTransaction(async (tx) => {
    // Todas as leituras primeiro (regra do Firestore: nenhuma escrita
    // pode acontecer antes de todas as leituras da transação) — o
    // `usageRef` só é conhecido depois de ler `bookingData`
    // (serviceId/period), por isso a sua leitura, condicional, tem de
    // ficar aqui também, antes de qualquer `tx.update`.
    const bookingSnap = await tx.get(bookingRef);
    const occurrenceSnap = await tx.get(occurrenceRef);

    if (!bookingSnap.exists || bookingSnap.data()?.status !== 'booked') {
      return { found: false, usageRefunded: false };
    }
    const bookingData = bookingSnap.data()!;

    // Janela de antecedência: só relevante se a sessão ainda está no
    // futuro (se já passou, `startAt <= now`, `hoursUntilStart` é
    // negativo, e portanto sempre fora da janela — correto, não faz
    // sentido devolver utilização de uma sessão já decorrida).
    const startAt = (occurrenceSnap.data()?.startAt as FirebaseFirestore.Timestamp | undefined)
      ?.toDate();
    const hoursUntilStart = startAt
      ? (startAt.getTime() - Date.now()) / (60 * 60 * 1000)
      : -Infinity;
    const withinWindow = minNoticeHours <= 0 || hoursUntilStart >= minNoticeHours;

    // `serviceId`/`period` só existem em bookings criados a partir
    // desta fase (ver nota em `booking.dart`) — sem eles não há forma
    // de saber que documento de `usage` decrementar; um booking antigo
    // (dados de seed pré-Fase-4) simplesmente não devolve nada, o que é
    // seguro (nunca tinha incrementado usage nenhum, para começar).
    const serviceId = bookingData.serviceId as string | undefined;
    const period = bookingData.period as string | undefined;
    // UC08-A — mesma correção de `lib/bookingLogic.ts#prepareRelease`:
    // uma sessão EXTRA nunca incrementou `usage`, por isso cancelá-la
    // não pode decrementar. Caso contrário o membro acabava com MENOS
    // utilizações gastas do que as que realmente usou.
    const isExtra = (bookingData.isExtra as boolean | undefined) ?? false;
    const usageRef =
      withinWindow && serviceId && period && !isExtra
        ? tenantRef.collection('usage').doc(`${memberId}_${serviceId}_${period}`)
        : null;
    const usageSnap = usageRef ? await tx.get(usageRef) : null;

    const activeCount =
      (occurrenceSnap.data()?.activeBookingCount as number | undefined) ?? 0;

    tx.update(bookingRef, {
      status: 'cancelled',
      cancelledAt: FieldValue.serverTimestamp(),
    });
    tx.update(occurrenceRef, {
      activeBookingCount: activeCount > 0 ? activeCount - 1 : 0,
    });

    // `usageRefunded` reflete o que REALMENTE aconteceu (não só "estava
    // dentro da janela"): se o membro nunca tinha consumido usage para
    // este período (ex.: serviço com UsageRule unlimited, ou
    // `usageSnap` nunca chegou a existir), não há nada para devolver,
    // mesmo estando dentro da janela — o cliente usa isto para mostrar
    // a mensagem final exata, em vez de assumir.
    let usageRefunded = false;
    if (usageRef && usageSnap?.exists) {
      const used = (usageSnap.data()?.used as number | undefined) ?? 0;
      tx.update(usageRef, {
        used: used > 0 ? used - 1 : 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
      usageRefunded = true;
    }

    return { found: true, usageRefunded };
  }, {
    // Mesma razão de `runBookingTransaction`: cancelar mexe no
    // `activeBookingCount` da MESMA aula que toda a gente está a
    // disputar. Ver a nota lá.
    maxAttempts: 10,
  });

  if (!result.found) {
    throw new HttpsError('not-found', 'Não tens uma marcação ativa nesta sessão.');
  }

  // Fase 11 — o lugar que acabou de vagar vai para o primeiro da
  // lista de espera. Depois do cancelamento estar concluído, e sem
  // nunca o desfazer se falhar: ver `lib/waitlist.ts`.
  const promotion = await promoteFromWaitlist({
    tenantRef,
    occurrenceId,
  });

  return {
    cancelled: true,
    usageRefunded: result.usageRefunded,
    promotedFromWaitlist: promotion.promotedMemberIds.length > 0,
  };
});
