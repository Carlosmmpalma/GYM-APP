// **Um plano ativo por membro** — atribuir um novo cancela o anterior.
//
// Este ficheiro testava o contrário: que um segundo plano era RECUSADO
// quando desse um serviço com o mesmo `Service.exclusiveGroup` do que
// o membro já tinha. Essa etiqueta era texto livre que o Gestor tinha
// de escrever à mão no ecrã dos serviços, para declarar quais eram
// alternativas uns dos outros — ninguém a preenchia, e o ecrã de
// atribuir partia-se em duas secções por causa dela sem nunca explicar
// porquê.
//
// Com um plano por membro não há combinações para proibir: a regra
// desapareceu em vez de ser melhor explicada. A proteção que interessa
// passou para o momento de MARCAR (ver `lib/overlap.ts`), onde se
// entende sem explicação nenhuma — ninguém está em dois sítios à mesma
// hora.
//
// Mesmo padrão de `booking-concurrency.test.ts`: chama a Cloud Function
// A SÉRIO através do Functions Emulator, autenticada com um custom
// token. Precisa de TRÊS emuladores (Firestore + Functions + Auth) e de
// `firebase/functions` já compilado.

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

  await adminFirestore.doc(`tenants/${TENANT_ID}/services/service_free`).set({
    name: 'Treino livre',
    active: true,
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/service_standard`).set({
    name: 'Aulas de grupo',
    active: true,
  });
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
// Cloud Function no emulador paga o arranque do runtime.
describe('createSubscription — um plano ativo por membro', () => {
  async function subscricoesAtivas(): Promise<string[]> {
    const snap = await adminFirestore
      .collection(`tenants/${TENANT_ID}/subscriptions`)
      .where('memberId', '==', MEMBER_ID)
      .where('status', '==', 'active')
      .get();
    return snap.docs.map((d) => d.get('planId') as string);
  }

  it('o primeiro plano é aceite', async () => {
    const result = await httpsCallable(managerFunctions, 'createSubscription')({
      memberId: MEMBER_ID,
      planId: 'plan_free',
      agreedPrice: 0,
      currency: 'EUR',
    });
    const data = result.data as { subscriptionId: string; replaced: string[] };
    expect(data.subscriptionId).toBeTruthy();
    // Nada substituído: não havia nada.
    expect(data.replaced).toEqual([]);
    expect(await subscricoesAtivas()).toEqual(['plan_free']);
  }, 15_000);

  it('um segundo plano SUBSTITUI o primeiro em vez de ser recusado', async () => {
    // Era aqui que a regra antiga recusava. Recusar obrigava a dois
    // passos ("vai cancelar primeiro") para o que é um só gesto na
    // cabeça de quem o faz — mudar de plano.
    const result = await httpsCallable(managerFunctions, 'createSubscription')({
      memberId: MEMBER_ID,
      planId: 'plan_standard',
      agreedPrice: 30,
      currency: 'EUR',
    });
    const data = result.data as { subscriptionId: string; replaced: string[] };
    expect(data.subscriptionId).toBeTruthy();
    // Devolve o NOME do que saiu, para o ecrã poder dizê-lo.
    expect(data.replaced).toHaveLength(1);

    // E fica exatamente um ativo. É esta a invariante toda: sem ela, o
    // limite semanal volta a ser ambíguo (`resolveEligibility` resolve-o
    // apanhando a primeira subscrição que der o serviço).
    expect(await subscricoesAtivas()).toEqual(['plan_standard']);
  }, 15_000);

  it('mudar outra vez continua a deixar um só', async () => {
    await httpsCallable(managerFunctions, 'createSubscription')({
      memberId: MEMBER_ID,
      planId: 'plan_hyrox',
      agreedPrice: 20,
      currency: 'EUR',
    });
    expect(await subscricoesAtivas()).toEqual(['plan_hyrox']);
  }, 15_000);
});
