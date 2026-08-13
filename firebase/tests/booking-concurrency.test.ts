// 🔴 Teste crítico da Fase 2 (guia-desenvolvimento.md):
//
//   "Teste de concorrência: simula duas marcações simultâneas na
//    última vaga e confirma que só uma é aceite... corre-o várias
//    vezes, não uma."
//
// Este teste NÃO chama o código Dart (não é possível correr Flutter
// aqui) — reimplementa em JS exatamente a mesma transação que
// lib/infrastructure/firebase/firebase_booking_repository.dart faz
// (ler ocorrência + booking, validar capacidade/duplicado, escrever
// booking + incrementar contador), contra o MESMO emulador e as
// MESMAS Security Rules. Isto prova que o mecanismo (Firestore
// Transactions + Rules com `isValidBookingCounterChange`) impede
// overbooking; não prova, por si só, que o ficheiro Dart não tem um
// bug de transcrição. Ver README.md, secção Fase 2, para o que falta
// verificar diretamente em Flutter.
//
// Corre com, a partir da raiz do projeto:
//   firebase emulators:exec --only firestore "npm --prefix firebase/tests test"

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const TENANT_ID = 'tenant_booking_test';
const OCCURRENCE_ID = 'occurrence_1';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    // projectId distinto de tenant-isolation.test.ts — ver o comentário
    // equivalente nesse ficheiro. Correr os dois ficheiros com o MESMO
    // projectId causava clearFirestore() de um a apagar os dados do
    // outro a meio da execução (o vitest corre ficheiros em paralelo por
    // omissão), o que explicava tanto marcações "rejeitadas" aqui sem
    // nenhum motivo de capacidade real, como um "Transaction lock
    // timeout" no outro ficheiro.
    projectId: 'demo-gym-saas-dev-booking-test',
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

async function seedOccurrence(capacity: number) {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`tenants/${TENANT_ID}`).set({ name: 'Tenant de teste' });
    await db.doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`).set({
      serviceId: 'service_1',
      capacity,
      status: 'scheduled',
      activeBookingCount: 0,
    });
  });
}

/**
 * Reimplementação em JS da transação de
 * firebase_booking_repository.dart#createBooking — ver nota no topo
 * do ficheiro.
 *
 * Nota sobre a retentativa abaixo (descoberta ao correr este teste, não
 * suposição): quando duas transações verdadeiramente simultâneas (via
 * `Promise.all`) tentam escrever o MESMO documento, o Firestore
 * resolve isso normalmente por concorrência otimista — a segunda
 * commit falha e o SDK repete-a automaticamente lendo dados frescos.
 * Mas contra o EMULADOR, quando a segunda transação colide, a
 * avaliação das Security Rules (`isValidBookingCounterChange`, que usa
 * `resource.data.diff(...)`) por vezes rebenta a meio com um erro do
 * motor de regras ("evaluation error"), que chega ao cliente como
 * `PERMISSION_DENIED` (código 7) — não como `ABORTED`. O SDK só repete
 * automaticamente erros `ABORTED`/de contenção; um `PERMISSION_DENIED`
 * é tratado como definitivo e não é repetido, mesmo sendo, neste caso,
 * um efeito colateral transitório da corrida, não uma negação real.
 * Confirmado correndo o teste com logging do erro: a mensagem inclui
 * sempre "evaluation error", nunca aparece nas rejeições de negócio
 * legítimas (essas vêm como Error('capacity-exceeded') lançado pelo
 * próprio código acima, nunca chegam a tocar o Firestore). Por isso só
 * repetimos quando a mensagem tem esta assinatura específica — uma
 * rejeição de negócio genuína nunca entra neste retry.
 */
async function attemptBooking(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  db: any,
  memberId: string,
): Promise<'booked' | 'rejected'> {
  const occurrenceRef = db.doc(
    `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`,
  );
  const bookingRef = occurrenceRef.collection('bookings').doc(memberId);

  const maxAttempts = 4;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await db.runTransaction(async (tx) => {
        const occSnap = await tx.get(occurrenceRef);
        const bookingSnap = await tx.get(bookingRef);

        const data = occSnap.data() as {
          status: string;
          capacity: number;
          activeBookingCount: number;
        };

        if (data.status !== 'scheduled') {
          throw new Error('not-bookable');
        }
        if (bookingSnap.exists && bookingSnap.data()?.status === 'booked') {
          throw new Error('already-booked');
        }
        if (data.activeBookingCount >= data.capacity) {
          throw new Error('capacity-exceeded');
        }

        tx.set(bookingRef, {
          memberId,
          status: 'booked',
          source: 'self',
          isExtra: false,
        });
        tx.update(occurrenceRef, {
          activeBookingCount: data.activeBookingCount + 1,
        });
      });
      return 'booked';
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      const isTransientRulesEngineGlitch = message.includes('evaluation error');

      if (isTransientRulesEngineGlitch && attempt < maxAttempts) {
        // Backoff curto e com jitter para não repetir instantaneamente
        // contra o mesmo conflito.
        await new Promise((resolve) =>
          setTimeout(resolve, 15 + Math.random() * 35),
        );
        continue;
      }

      // eslint-disable-next-line no-console
      console.error(
        `[attemptBooking:${memberId}] rejeitado (tentativa ${attempt}) — motivo:`,
        message,
      );
      return 'rejected';
    }
  }
  // Inatingível — o loop sempre faz return ou continue.
  return 'rejected';
}

describe('Concorrência na última vaga (Fase 2, 🔴 crítico)', () => {
  it('duas marcações simultâneas numa ocorrência de capacidade 1 — só uma vence, repetido 5x', async () => {
    for (let attempt = 1; attempt <= 5; attempt++) {
      await seedOccurrence(1);

      const memberA = testEnv
        .authenticatedContext('member_a', { tenantId: TENANT_ID, roles: ['member'] })
        .firestore();
      const memberB = testEnv
        .authenticatedContext('member_b', { tenantId: TENANT_ID, roles: ['member'] })
        .firestore();

      const [resultA, resultB] = await Promise.all([
        attemptBooking(memberA, 'member_a'),
        attemptBooking(memberB, 'member_b'),
      ]);

      const outcomes = [resultA, resultB];
      const bookedCount = outcomes.filter((r) => r === 'booked').length;
      const rejectedCount = outcomes.filter((r) => r === 'rejected').length;

      expect(
        bookedCount,
        `tentativa ${attempt}: esperava exatamente 1 marcação aceite, houve ${bookedCount}`,
      ).toBe(1);
      expect(rejectedCount).toBe(1);

      // Confirma que o contador reflete exatamente 1, nunca 2 — é isto
      // que prova que não houve overbooking, não só que uma promise
      // rejeitou por outro motivo qualquer.
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const occSnap = await context
          .firestore()
          .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
          .get();
        expect(occSnap.data()?.activeBookingCount).toBe(1);
      });
    }
  });

  it('capacidade 2 com duas marcações simultâneas — ambas vencem', async () => {
    await seedOccurrence(2);

    const memberA = testEnv
      .authenticatedContext('member_a', { tenantId: TENANT_ID, roles: ['member'] })
      .firestore();
    const memberB = testEnv
      .authenticatedContext('member_b', { tenantId: TENANT_ID, roles: ['member'] })
      .firestore();

    const [resultA, resultB] = await Promise.all([
      attemptBooking(memberA, 'member_a'),
      attemptBooking(memberB, 'member_b'),
    ]);

    expect(resultA).toBe('booked');
    expect(resultB).toBe('booked');

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const occSnap = await context
        .firestore()
        .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
        .get();
      expect(occSnap.data()?.activeBookingCount).toBe(2);
    });
  });
});
