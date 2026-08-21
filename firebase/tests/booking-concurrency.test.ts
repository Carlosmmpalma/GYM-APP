// 🔴 Teste crítico da Fase 2 (guia-desenvolvimento.md), reescrito na
// Fase 5 depois de detetado partido:
//
//   "Teste de concorrência: simula duas marcações simultâneas na
//    última vaga e confirma que só uma é aceite... corre-o várias
//    vezes, não uma."
//
// Versão original (Fase 2): reimplementava em TS a transação
// client-side que `firebase_booking_repository.dart` fazia na altura,
// contra o Firestore Emulator + Security Rules diretamente
// (`@firebase/rules-unit-testing`). A Fase 4 moveu `createBooking`
// para uma Cloud Function (Admin SDK) e fechou `sessionOccurrences`/
// `bookings` para escrita de QUALQUER cliente (`firestore.rules`) —
// desde então este ficheiro testava um caminho morto: as duas
// tentativas de escrita direta caíam sempre em `PERMISSION_DENIED`
// antes de chegar a testar concorrência nenhuma. Ninguém tinha
// reparado porque ninguém tinha corrido isto de facto até à Fase 5
// (ver `app/README.md`, secção Fase 5, "Décimo terceiro problema").
//
// Esta versão chama a Cloud Function `createBooking` A SÉRIO, através
// do Functions Emulator, autenticado como dois membros distintos com
// um custom token (claims `tenantId`/`roles` embutidas diretamente no
// token — técnica documentada pela Firebase para testes, evita ter de
// criar utilizadores reais no Auth Emulator só para isto). A
// concorrência na última vaga é agora garantida pela transação dentro
// de `lib/bookingLogic.ts#runBookingTransaction` (Admin SDK) — é essa
// transação que este teste está a exercitar, não mais uma reimplementação
// paralela dela.
//
// Precisa de TRÊS emuladores (Firestore + Functions + Auth) — ao
// contrário dos outros ficheiros deste diretório, que só precisam do
// Firestore. E precisa que `firebase/functions` esteja compilado
// (`lib/index.js`), porque é isso que o Functions Emulator carrega.
// Corre com, a partir da raiz do projeto:
//
//   cd firebase/functions
//   npm run build
//   cd ../..
//   firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth "npm --prefix firebase/tests test"
//
// (Os outros 4 ficheiros deste diretório continuam a passar
// normalmente com os emuladores extra ligados — só não precisam deles.)

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { deleteApp, initializeApp as initializeClientApp, type FirebaseApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// AO CONTRÁRIO dos outros ficheiros deste diretório, este NÃO pode usar
// um projectId próprio: uma Cloud Function a correr no emulador está
// SEMPRE ligada ao projeto passado em `--project` a
// `emulators:exec`/`emulators:start` (aqui, `demo-gym-saas-dev` —
// `initializeApp()` sem argumentos em `firebase/functions/src/index.ts`
// resolve o projeto a partir do ambiente do runtime, não de nada que
// este ficheiro controle). Descoberto ao correr isto pela primeira vez:
// com um projectId próprio, `createBooking` respondia sempre
// `not-found` — a função lia/escrevia sob `demo-gym-saas-dev`, o teste
// semeava sob outro projeto completamente separado dentro do mesmo
// emulador. Isolamento fica só ao nível do tenant (`TENANT_ID` abaixo,
// nunca usado por `firebase/scripts/seed.mjs` nem pelos outros
// ficheiros de teste), não do projeto.
const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_booking_fn_test';
const SERVICE_ID = 'service_1';
const OCCURRENCE_ID = 'occurrence_1';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-booking-fn-test');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];

/**
 * Assina um custom token com `tenantId`/`roles` como "additional
 * claims" e troca-o por uma sessão autenticada num client SDK próprio
 * (uma app nomeada por membro, para os dois poderem chamar em
 * simultâneo sem pisarem a sessão um do outro). As additional claims
 * de um custom token propagam-se diretamente para o ID token
 * resultante — é assim que `requireAuthenticated`
 * (`lib/callerContext.ts`) as vai encontrar em
 * `request.auth.token.tenantId`/`roles`, exatamente como aconteceria
 * com custom claims reais definidas via `setCustomUserClaims` (que a
 * app de produção usa, `createMember.ts`/`createStaff.ts`).
 */
async function signedInFunctionsClient(
  appName: string,
  uid: string,
  claims: { tenantId: string; roles: string[] },
): Promise<Functions> {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    appName,
  );
  clientApps.push(app);

  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  const customToken = await adminAuth.createCustomToken(uid, claims);
  await signInWithCustomToken(auth, customToken);

  // A região TEM de bater certo com o `setGlobalOptions` de
  // `functions/src/index.ts`: com a região errada, o cliente procura as
  // funções em `us-central1`, onde não existe nada, e recebe
  // `not-found` em tudo.
  const functions = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return functions;
}

async function resetOccurrence(capacity: number) {
  const occurrenceRef = adminFirestore.doc(
    `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`,
  );
  // Admin SDK ignora Security Rules — não precisa de nenhum
  // `withSecurityRulesDisabled` equivalente (isso era só necessário
  // com `@firebase/rules-unit-testing`, que este ficheiro já não usa).
  await adminFirestore.recursiveDelete(occurrenceRef).catch(() => undefined);
  await occurrenceRef.set({
    serviceId: SERVICE_ID,
    startAt: Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
    endAt: Timestamp.fromDate(new Date(Date.now() + 25 * 60 * 60 * 1000)),
    capacity,
    status: 'scheduled',
    activeBookingCount: 0,
  });
}

beforeAll(async () => {
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Tenant de teste (Fase 5)' });
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`).set({
    name: 'Aula de Grupo (teste)',
    active: true,
  });
  // `createBooking.ts` (via `resolveEligibility`, `lib/bookingLogic.ts`)
  // exige uma subscription ativa antes de sequer chegar à transação de
  // capacidade — sem isto, as duas tentativas seriam sempre rejeitadas
  // com "não elegível", nunca testando concorrência nenhuma. Não existe
  // `plans/{planId}/services/{serviceId}` — `resolveEligibility`
  // assume `unlimited` quando esse documento não existe, o que é
  // exatamente o que este teste quer (isolar só a variável de
  // capacidade, sem o limite semanal da Fase 4 a interferir).
  for (const memberId of ['member_a', 'member_b']) {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/sub_${memberId}`)
      .set({
        memberId,
        planId: 'plan_test',
        status: 'active',
        startDate: FieldValue.serverTimestamp(),
        agreedPrice: 0,
        currency: 'EUR',
        activeServiceIds: [SERVICE_ID],
      });
  }
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

async function attemptBooking(functions: Functions, memberId: string): Promise<'booked' | 'rejected'> {
  try {
    await httpsCallable(functions, 'createBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId,
    });
    return 'booked';
  } catch (err) {
    const code = (err as { code?: string } | undefined)?.code ?? 'unknown';
    const message = err instanceof Error ? err.message : String(err);
    // eslint-disable-next-line no-console
    console.error(`[attemptBooking:${memberId}] rejeitado — código: ${code} — ${message}`);
    return 'rejected';
  }
}

describe('Concorrência na última vaga (Fase 2, 🔴 crítico — via Cloud Function real, Fase 5)', () => {
  it('duas marcações simultâneas numa ocorrência de capacidade 1 — só uma vence, repetido 5x', async () => {
    const functionsA = await signedInFunctionsClient('client-a-cap1', 'member_a', {
      tenantId: TENANT_ID,
      roles: ['member'],
    });
    const functionsB = await signedInFunctionsClient('client-b-cap1', 'member_b', {
      tenantId: TENANT_ID,
      roles: ['member'],
    });

    for (let attempt = 1; attempt <= 5; attempt++) {
      await resetOccurrence(1);

      const [resultA, resultB] = await Promise.all([
        attemptBooking(functionsA, 'member_a'),
        attemptBooking(functionsB, 'member_b'),
      ]);

      const outcomes = [resultA, resultB];
      const bookedCount = outcomes.filter((r) => r === 'booked').length;
      const rejectedCount = outcomes.filter((r) => r === 'rejected').length;

      expect(
        bookedCount,
        `tentativa ${attempt}: esperava exatamente 1 marcação aceite, houve ${bookedCount}`,
      ).toBe(1);
      expect(rejectedCount).toBe(1);

      // Confirma que o contador reflete exatamente 1, nunca 2 — prova
      // que não houve overbooking, não só que uma chamada falhou por
      // outro motivo qualquer.
      const occSnap = await adminFirestore
        .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
        .get();
      expect(occSnap.data()?.activeBookingCount).toBe(1);
    }
  }, 30_000);

  it('capacidade 2 com duas marcações simultâneas — ambas vencem', async () => {
    await resetOccurrence(2);

    const functionsA = await signedInFunctionsClient('client-a-cap2', 'member_a', {
      tenantId: TENANT_ID,
      roles: ['member'],
    });
    const functionsB = await signedInFunctionsClient('client-b-cap2', 'member_b', {
      tenantId: TENANT_ID,
      roles: ['member'],
    });

    const [resultA, resultB] = await Promise.all([
      attemptBooking(functionsA, 'member_a'),
      attemptBooking(functionsB, 'member_b'),
    ]);

    expect(resultA).toBe('booked');
    expect(resultB).toBe('booked');

    const occSnap = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .get();
    expect(occSnap.data()?.activeBookingCount).toBe(2);
  }, 15_000);
});

// Fase 8 (auditoria funcional, UC06/UC07/UC08/UC09 fechado) —
// "antecedência mínima para marcar, configurável pelo Gestor". Reusa o
// mesmo tenant/serviço/subscriptions já semeados em `beforeAll` acima
// — só varia `startAt` da ocorrência e o documento
// `config/bookingPolicy`, por isso vive no mesmo ficheiro em vez de
// duplicar todo o setup de custom token/Functions emulator.
describe('Antecedência mínima para marcar (Fase 8, UC06/07/08/09 fechado)', () => {
  const bookingPolicyRef = adminFirestore.doc(
    `tenants/${TENANT_ID}/config/bookingPolicy`,
  );

  async function resetOccurrenceStartingIn(minutesFromNow: number) {
    const occurrenceRef = adminFirestore.doc(
      `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`,
    );
    await adminFirestore.recursiveDelete(occurrenceRef).catch(() => undefined);
    await occurrenceRef.set({
      serviceId: SERVICE_ID,
      startAt: Timestamp.fromDate(new Date(Date.now() + minutesFromNow * 60 * 1000)),
      endAt: Timestamp.fromDate(new Date(Date.now() + (minutesFromNow + 60) * 60 * 1000)),
      capacity: 5,
      status: 'scheduled',
      activeBookingCount: 0,
    });
  }

  afterAll(async () => {
    // Não deixar `minBookingNoticeMinutes` configurado para trás —
    // outros ficheiros/testes deste diretório assumem `0` (sem
    // restrição) por omissão, mesmo raciocínio do `resetOccurrence`
    // acima para `activeBookingCount`.
    await bookingPolicyRef.delete().catch(() => undefined);
  });

  it('rejeita marcar dentro da janela configurada (failed-precondition, reason too-close-to-start)', async () => {
    await bookingPolicyRef.set({ minBookingNoticeMinutes: 120 }, { merge: true });
    await resetOccurrenceStartingIn(30);

    const functions = await signedInFunctionsClient('client-notice-too-close', 'member_a', {
      tenantId: TENANT_ID,
      roles: ['member'],
    });

    await expect(
      httpsCallable(functions, 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: 'member_a',
      }),
    ).rejects.toMatchObject({
      code: 'functions/failed-precondition',
      details: { reason: 'too-close-to-start', minutesRequired: 120 },
    });

    const occSnap = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .get();
    expect(occSnap.data()?.activeBookingCount).toBe(0);
  }, 15_000);

  it('permite marcar fora da janela configurada', async () => {
    await bookingPolicyRef.set({ minBookingNoticeMinutes: 120 }, { merge: true });
    await resetOccurrenceStartingIn(180);

    const functions = await signedInFunctionsClient('client-notice-ok', 'member_a', {
      tenantId: TENANT_ID,
      roles: ['member'],
    });

    const result = await attemptBooking(functions, 'member_a');
    expect(result).toBe('booked');

    const occSnap = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .get();
    expect(occSnap.data()?.activeBookingCount).toBe(1);
  }, 15_000);
});
