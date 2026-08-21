// Fase 8 (auditoria funcional, UC26 fechado) — "Sem acompanhamento" e
// Standard/Plus/Premium não são produtos independentes, são NÍVEIS DO
// MESMO PRODUTO: um membro nunca pode ter subscriptions ativas a dois
// serviços com o mesmo `Service.exclusiveGroup`, mesmo quando são
// serviços DIFERENTES — o conflito por `activeServiceIds` já existente
// em `createSubscription.ts` (Fase 3) só apanhava dois planos a dar
// acesso ao MESMO serviço, nunca este caso.
//
// Mesmo padrão de `booking-concurrency.test.ts`: chama a Cloud
// Function `createSubscription` A SÉRIO através do Functions Emulator,
// autenticado com um custom token — é a única forma de exercitar a
// lógica de negócio real (Admin SDK), não uma reimplementação paralela
// dela. Precisa de TRÊS emuladores (Firestore + Functions + Auth) e de
// `firebase/functions` já compilado (`lib/index.js`). Corre com, a
// partir da raiz do projeto:
//
//   cd firebase/functions
//   npm run build
//   cd ../..
//   firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth "npm --prefix firebase/tests test"

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { deleteApp, initializeApp as initializeClientApp, type FirebaseApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// Mesmo raciocínio de `booking-concurrency.test.ts`: uma Cloud
// Function no emulador está SEMPRE ligada ao projeto passado em
// `--project` a `emulators:exec` — não pode ter um projectId próprio.
const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_exclusive_group_test';
const MEMBER_ID = 'member_exclusive_group_test';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-exclusive-group-test');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFunctions: Functions;

async function signedInFunctionsClient(
  appName: string,
  uid: string,
  claims: { tenantId: string; roles: string[] },
): Promise<Functions> {
  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-api-key' }, appName);
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

async function createPlanGranting(planId: string, serviceId: string) {
  await adminFirestore.doc(`tenants/${TENANT_ID}/plans/${planId}`).set({
    name: planId,
    active: true,
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/plans/${planId}/services/${serviceId}`).set({
    enabled: true,
    usage: { type: 'unlimited' },
  });
}

beforeAll(async () => {
  // As três asserções abaixo são sequenciais e dependem umas das
  // outras (a 2ª só conflitua porque a 1ª criou a subscription).
  // Limpar subscriptions residuais garante que o ficheiro passa também
  // quando corrido contra um emulador que já tenha estado a correr —
  // mesmo raciocínio do `resetOccurrence` em `booking-concurrency.test.ts`.
  const stale = await adminFirestore
    .collection(`tenants/${TENANT_ID}/subscriptions`)
    .get();
  await Promise.all(stale.docs.map((doc) => doc.ref.delete()));

  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Tenant de teste (Fase 8)' });
  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`).set({
    name: 'Membro de teste',
    memberNumber: '000001',
    status: 'active',
  });

  // Dois serviços DIFERENTES, mesmo `exclusiveGroup` — o caso que só a
  // Fase 8 passou a apanhar.
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/service_free`).set({
    name: 'Sem acompanhamento',
    active: true,
    exclusiveGroup: 'sala',
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/service_standard`).set({
    name: 'Aula de Grupo (Standard)',
    active: true,
    exclusiveGroup: 'sala',
  });
  // Serviço sem grupo nenhum — livremente combinável, prova que o
  // novo código não bloqueia em excesso.
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/service_hyrox`).set({
    name: 'Hyrox',
    active: true,
  });

  await createPlanGranting('plan_free', 'service_free');
  await createPlanGranting('plan_standard', 'service_standard');
  await createPlanGranting('plan_hyrox', 'service_hyrox');

  managerFunctions = await signedInFunctionsClient('client-manager-exclusive-group', 'manager_1', {
    tenantId: TENANT_ID,
    roles: ['manager'],
  });
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

// Timeouts explícitos (15s) em vez dos 5s por omissão do vitest, mesmo
// motivo de `booking-concurrency.test.ts`: a PRIMEIRA invocação de uma
// Cloud Function no emulador paga o arranque do runtime, e este
// ficheiro corre em paralelo com o de concorrência (que satura o
// emulador com 10 chamadas simultâneas) — 5s não chegam de forma
// fiável, mesmo quando a função em si responde em ~250ms.
describe('createSubscription — exclusividade por Service.exclusiveGroup (Fase 8, UC26 fechado)', () => {
  it('primeira subscription do grupo "sala" é aceite', async () => {
    const result = await httpsCallable(managerFunctions, 'createSubscription')({
      memberId: MEMBER_ID,
      planId: 'plan_free',
      agreedPrice: 0,
      currency: 'EUR',
    });
    expect((result.data as { subscriptionId: string }).subscriptionId).toBeTruthy();
  }, 15_000);

  it('segunda subscription do MESMO grupo, serviço DIFERENTE, é rejeitada', async () => {
    await expect(
      httpsCallable(managerFunctions, 'createSubscription')({
        memberId: MEMBER_ID,
        planId: 'plan_standard',
        agreedPrice: 30,
        currency: 'EUR',
      }),
    ).rejects.toMatchObject({
      code: 'functions/already-exists',
      details: {
        conflictingServiceNames: ['Sem acompanhamento'],
      },
    });
  }, 15_000);

  it('subscription a um serviço SEM grupo (Hyrox) continua permitida', async () => {
    const result = await httpsCallable(managerFunctions, 'createSubscription')({
      memberId: MEMBER_ID,
      planId: 'plan_hyrox',
      agreedPrice: 20,
      currency: 'EUR',
    });
    expect((result.data as { subscriptionId: string }).subscriptionId).toBeTruthy();
  }, 15_000);
});
