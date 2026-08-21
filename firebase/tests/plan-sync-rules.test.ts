// Fase 11 (bug reportado) — acrescentar um serviço a um plano tem de
// valer para quem JÁ tem esse plano.
//
// `activeServiceIds` de uma subscrição é uma cópia dos serviços do
// plano, tirada no momento da criação, e nada a atualizava. O Gestor
// acrescentava "Treino Livre" ao plano da aluna e a app continuava a
// dizer-lhe "o teu plano não inclui treino livre" — porque é essa cópia
// que TUDO consulta: o filtro do ecrã, a validação de `createBooking`, e
// a query de membros elegíveis.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import {
  deleteApp,
  initializeApp as initializeClientApp,
  type FirebaseApp,
} from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_plan_sync_test';
const MANAGER_ID = 'plansync_manager';
const MEMBER_ID = 'plansync_member';
const PLAN_ID = 'plan_standard';
const AULAS = 'service_aulas';
const LIVRE = 'service_livre';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-plansync');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFunctions: Functions;
let memberFunctions: Functions;

async function signedIn(name: string, uid: string, roles: string[]) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    name,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const functions = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return functions;
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });

  for (const [id, name] of [[AULAS, 'Aulas'], [LIVRE, 'Treino Livre']] as const) {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/services/${id}`)
      .set({ name, active: true });
  }

  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}`)
    .set({ name: 'Standard', active: true, currentPrice: 40, currency: 'EUR' });

  // O plano começa só com Aulas.
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}/services/${AULAS}`)
    .set({ enabled: true, usage: { type: 'unlimited' } });

  // A aluna subscreve ANTES de o Treino Livre existir no plano — é
  // exatamente a situação reportada.
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/subscriptions/sub_1`)
    .set({
      memberId: MEMBER_ID,
      planId: PLAN_ID,
      status: 'active',
      agreedPrice: 40,
      currency: 'EUR',
      activeServiceIds: [AULAS],
      startDate: new Date(),
    });

  // Uma subscrição CANCELADA do mesmo plano: o histórico não se
  // reescreve.
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/subscriptions/sub_antiga`)
    .set({
      memberId: 'outro_membro',
      planId: PLAN_ID,
      status: 'cancelled',
      agreedPrice: 40,
      currency: 'EUR',
      activeServiceIds: [AULAS],
      startDate: new Date(),
    });

  for (const uid of [MANAGER_ID, MEMBER_ID]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }

  managerFunctions = await signedIn('plansync-manager', MANAGER_ID, ['manager']);
  memberFunctions = await signedIn('plansync-member', MEMBER_ID, ['member']);
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

describe('syncPlanSubscriptions', () => {
  it('propaga um serviço acrescentado a quem já tem o plano', async () => {
    // O Gestor acrescenta Treino Livre ao plano.
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}/services/${LIVRE}`)
      .set({ enabled: true, usage: { type: 'unlimited' } });

    // Antes de sincronizar, a aluna continua sem ele — que era o bug.
    const antes = await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/sub_1`)
      .get();
    expect(antes.get('activeServiceIds')).toEqual([AULAS]);

    const result = await httpsCallable(
      managerFunctions,
      'syncPlanSubscriptions',
    )({ planId: PLAN_ID });
    expect((result.data as { updated: number }).updated).toBe(1);

    const depois = await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/sub_1`)
      .get();
    expect((depois.get('activeServiceIds') as string[]).sort()).toEqual(
      [AULAS, LIVRE].sort(),
    );
  });

  it('não reescreve subscrições canceladas — isso é histórico', async () => {
    const antiga = await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/sub_antiga`)
      .get();
    expect(antiga.get('activeServiceIds')).toEqual([AULAS]);
  });

  it('desativar um serviço também propaga', async () => {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}/services/${LIVRE}`)
      .set({ enabled: false, usage: { type: 'unlimited' } });

    await httpsCallable(managerFunctions, 'syncPlanSubscriptions')({
      planId: PLAN_ID,
    });

    const depois = await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/sub_1`)
      .get();
    expect(depois.get('activeServiceIds')).toEqual([AULAS]);
  });

  it('correr outra vez sem mudanças não escreve nada', async () => {
    const result = await httpsCallable(
      managerFunctions,
      'syncPlanSubscriptions',
    )({ planId: PLAN_ID });
    expect((result.data as { updated: number }).updated).toBe(0);
  });

  it('um aluno NÃO pode sincronizar planos', async () => {
    await expect(
      httpsCallable(memberFunctions, 'syncPlanSubscriptions')({
        planId: PLAN_ID,
      }),
    ).rejects.toThrow();
  });
});
