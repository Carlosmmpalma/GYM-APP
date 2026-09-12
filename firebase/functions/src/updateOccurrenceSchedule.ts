import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { isoWeekKey, isoWeekRange } from './lib/isoWeek';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  occurrenceId: z.string().min(1),
  startAt: z.string().datetime(),
  endAt: z.string().datetime(),
  capacity: z.number().int().min(1).max(500),
  instructorId: z.string().nullable().optional(),
  modalityId: z.string().nullable().optional(),
});

/**
 * Mudar a hora, a lotação ou o instrutor de uma aula **que já tem
 * inscritos**.
 *
 * ## O bug que isto corrige
 *
 * Isto era uma escrita direta do cliente sobre `sessionOccurrences`, e
 * tocava só no documento da aula. Parecia inofensivo porque a aula é um
 * documento e a mudança é uma data.
 *
 * Mas cada marcação guarda uma **cópia** da `startAt` e o `period` — a
 * semana ISO em que foi contada — e o limite semanal do plano vive num
 * documento `usage/{membro}_{serviço}_{semana}`. Mover uma aula de uma
 * semana para outra deixava a utilização contada na semana antiga, e a
 * semana de destino outra vez livre.
 *
 * O custo não era um número errado num ecrã: com um plano de 1x por
 * semana, o aluno passava a ter DUAS aulas na semana para onde a aula
 * foi movida. O limite do plano deixava de valer, e ninguém dava por
 * isso porque tudo continuava a parecer certo.
 *
 * ## O que faz agora
 *
 * Tudo numa transação, porque ou a aula e as marcações mudam juntas ou
 * é pior do que não mudar nada:
 *
 *   1. atualiza a aula;
 *   2. atualiza a `startAt` copiada em cada marcação ATIVA;
 *   3. se a semana ISO mudou, move a utilização — tira uma da semana
 *      antiga e põe uma na nova, membro a membro.
 *
 * ## O que NÃO faz, e porquê
 *
 * **Não recusa** quando alguém fica acima do limite na semana nova. É o
 * estúdio a mudar o horário, não o membro a marcar outra aula: recusar
 * deixaria o Gestor sem forma de corrigir uma hora errada só porque um
 * aluno já tem a semana cheia. Devolve quantos ficaram assim, para o
 * ecrã o poder dizer.
 *
 * **Não toca em marcações canceladas.** Quem cancelou já teve a
 * utilização devolvida; mexer-lhe outra vez dava-lhe uma a mais.
 *
 * **Não trata sessões extra**: nunca consumiram utilização (ver
 * `runBookingTransaction`), por isso não há nada para mover.
 */
export const updateOccurrenceSchedule = onCall(async (request) => {
  const caller = requireManagerOrInstructor(request);
  const input = parseInput(inputSchema, request.data ?? {});

  const startAt = new Date(input.startAt);
  const endAt = new Date(input.endAt);
  if (endAt <= startAt) {
    throw new HttpsError(
      'invalid-argument',
      'A hora de fim tem de ser depois da hora de início.',
    );
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const occurrenceRef = tenantRef
    .collection('sessionOccurrences')
    .doc(input.occurrenceId);

  return firestore.runTransaction(async (tx) => {
    const occSnap = await tx.get(occurrenceRef);
    if (!occSnap.exists) {
      throw new HttpsError('not-found', 'Essa aula já não existe.');
    }

    const antiga = (occSnap.get('startAt') as Timestamp | undefined)?.toDate();
    const semanaAntiga = antiga ? isoWeekKey(antiga) : null;
    const semanaNova = isoWeekKey(startAt);
    const mudouDeSemana = semanaAntiga !== null && semanaAntiga !== semanaNova;

    const bookingsSnap = await tx.get(
      occurrenceRef.collection('bookings').where('status', '==', 'booked'),
    );

    // Reduzir a lotação abaixo do que já está marcado teria de decidir
    // quem sai, e isso é uma decisão do estúdio com nome e apelido —
    // existe para isso `removeMembersFromOccurrence`.
    if (input.capacity < bookingsSnap.size) {
      throw new HttpsError(
        'failed-precondition',
        `Esta aula tem ${bookingsSnap.size} inscrito(s). Para reduzir a ` +
          'lotação, tira primeiro quem sai.',
      );
    }

    // Todas as leituras antes de qualquer escrita — regra do Firestore.
    // Daí duas passagens sobre as mesmas marcações.
    const movimentos: {
      bookingRef: FirebaseFirestore.DocumentReference;
      antigoRef: FirebaseFirestore.DocumentReference | null;
      antigoUsado: number;
      novoRef: FirebaseFirestore.DocumentReference | null;
      novoUsado: number;
      excedeu: boolean;
      limite: number | null;
    }[] = [];

    if (mudouDeSemana) {
      for (const booking of bookingsSnap.docs) {
        const memberId = booking.get('memberId') as string;
        const serviceId = booking.get('serviceId') as string | undefined;
        const periodoAntigo = booking.get('period') as string | undefined;
        const isExtra = (booking.get('isExtra') as boolean | undefined) ?? false;

        // Sem serviço ou sem período não houve contagem para mover
        // (marcações anteriores a estes campos existirem), e uma sessão
        // extra nunca contou.
        if (!serviceId || !periodoAntigo || isExtra) {
          movimentos.push({
            bookingRef: booking.ref,
            antigoRef: null,
            antigoUsado: 0,
            novoRef: null,
            novoUsado: 0,
            excedeu: false,
            limite: null,
          });
          continue;
        }

        const antigoRef = tenantRef
          .collection('usage')
          .doc(`${memberId}_${serviceId}_${periodoAntigo}`);
        const novoRef = tenantRef
          .collection('usage')
          .doc(`${memberId}_${serviceId}_${semanaNova}`);
        const [antigoSnap, novoSnap] = await Promise.all([
          tx.get(antigoRef),
          tx.get(novoRef),
        ]);

        movimentos.push({
          bookingRef: booking.ref,
          antigoRef: antigoSnap.exists ? antigoRef : null,
          antigoUsado: (antigoSnap.get('used') as number | undefined) ?? 0,
          novoRef,
          novoUsado: (novoSnap.get('used') as number | undefined) ?? 0,
          excedeu: false,
          limite: null,
        });
      }
    }

    // --- daqui para baixo, só escritas ---
    tx.update(occurrenceRef, {
      startAt: Timestamp.fromDate(startAt),
      endAt: Timestamp.fromDate(endAt),
      capacity: input.capacity,
      instructorId: input.instructorId ?? null,
      modalityId: input.modalityId ?? null,
    });

    for (const booking of bookingsSnap.docs) {
      tx.update(booking.ref, {
        startAt: Timestamp.fromDate(startAt),
        ...(mudouDeSemana ? { period: semanaNova } : {}),
      });
    }

    if (mudouDeSemana) {
      const { start: inicioNovo, end: fimNovo } = isoWeekRange(startAt);
      for (const m of movimentos) {
        if (m.antigoRef) {
          tx.update(m.antigoRef, {
            used: m.antigoUsado > 0 ? m.antigoUsado - 1 : 0,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
        if (m.novoRef) {
          const booking = bookingsSnap.docs.find(
            (d) => d.ref.path === m.bookingRef.path,
          )!;
          tx.set(
            m.novoRef,
            {
              memberId: booking.get('memberId'),
              serviceId: booking.get('serviceId'),
              period: semanaNova,
              periodType: 'week',
              periodStart: Timestamp.fromDate(inicioNovo),
              periodEnd: Timestamp.fromDate(fimNovo),
              used: m.novoUsado + 1,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }
    }

    return {
      bookingsUpdated: bookingsSnap.size,
      weekChanged: mudouDeSemana,
    };
  });
});
