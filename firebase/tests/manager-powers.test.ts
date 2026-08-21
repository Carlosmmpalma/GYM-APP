// Fase 11 — os poderes que o Gestor ganhou para não ter de chamar um
// developer, e as travas que os tornam seguros.
//
// O que interessa testar aqui não é o caminho feliz (esse vê-se a usar
// a app) — são as recusas:
//
//   1. Só um Gestor faz isto. Um instrutor ou um aluno não.
//   2. Só dentro do PRÓPRIO ginásio. O `userId` vem do cliente, e um
//      Gestor não pode usá-lo para chegar a outro tenant.
//   3. Um Gestor não se despromove a si próprio — ficaria trancado
//      fora, a precisar exatamente do developer que isto dispensa.
//
// Precisa dos emuladores Firestore + Functions + Auth e de
// `firebase/functions` compilado. Ver `booking-concurrency.test.ts`.

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
const TENANT_ID = 'tenant_powers_test';
const OTHER_TENANT_ID = 'tenant_powers_other';

const MANAGER_ID = 'powers_manager';
const SECOND_MANAGER_ID = 'powers_manager_2';
const INSTRUCTOR_ID = 'powers_instructor';
const MEMBER_ID = 'powers_member';
const OTHER_TENANT_MEMBER_ID = 'powers_member_other_tenant';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-powers-test');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFunctions: Functions;
let instructorFunctions: Functions;
let memberFunctions: Functions;

async function signedInFunctions(
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
  await signInWithCustomToken(auth, await adminAuth.createCustomToken(uid, claims));
  // A região TEM de bater certo com o `setGlobalOptions` de
  // `functions/src/index.ts`: com a região errada, o cliente procura as
  // funções em `us-central1`, onde não existe nada, e recebe
  // `not-found` em tudo.
  const functions = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return functions;
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.recursiveDelete(
    adminFirestore.doc(`tenants/${OTHER_TENANT_ID}`),
  );

  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Ginásio A' });
  await adminFirestore.doc(`tenants/${OTHER_TENANT_ID}`).set({ name: 'Ginásio B' });

  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`).set({
    name: 'Aluno de teste',
    memberNumber: '000042',
    status: 'active',
  });
  await adminFirestore
    .doc(`tenants/${OTHER_TENANT_ID}/members/${OTHER_TENANT_MEMBER_ID}`)
    .set({ name: 'Aluno de outro ginásio', memberNumber: '000001', status: 'active' });

  for (const [uid, roles] of [
    [MANAGER_ID, ['manager']],
    [SECOND_MANAGER_ID, ['manager']],
    [INSTRUCTOR_ID, ['instructor']],
  ] as const) {
    await adminFirestore.doc(`tenants/${TENANT_ID}/staff/${uid}`).set({
      name: uid,
      email: `${uid}@example.test`,
      roles: [...roles],
      status: 'active',
    });
  }

  for (const uid of [
    MANAGER_ID,
    SECOND_MANAGER_ID,
    INSTRUCTOR_ID,
    MEMBER_ID,
    OTHER_TENANT_MEMBER_ID,
  ]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }

  managerFunctions = await signedInFunctions('powers-manager', MANAGER_ID, {
    tenantId: TENANT_ID,
    roles: ['manager'],
  });
  instructorFunctions = await signedInFunctions('powers-instructor', INSTRUCTOR_ID, {
    tenantId: TENANT_ID,
    roles: ['instructor'],
  });
  memberFunctions = await signedInFunctions('powers-member', MEMBER_ID, {
    tenantId: TENANT_ID,
    roles: ['member'],
  });
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

describe('resetUserPassword', () => {
  it('o Gestor repõe a password de um aluno e recebe a temporária', async () => {
    const result = await httpsCallable(managerFunctions, 'resetUserPassword')({
      userId: MEMBER_ID,
    });
    const { temporaryPassword } = result.data as { temporaryPassword: string };

    expect(temporaryPassword).toBeTruthy();
    expect(temporaryPassword.length).toBeGreaterThanOrEqual(10);

    // A app tem de forçar a troca no primeiro login (UC22) — sem esta
    // marca, a password entregue em mão ficava a valer para sempre.
    const member = await adminFirestore
      .doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`)
      .get();
    expect(member.get('passwordTemporaria')).toBe(true);
    expect(member.get('passwordResetBy')).toBe(MANAGER_ID);
  });

  it('um Instrutor NÃO consegue repor passwords', async () => {
    await expect(
      httpsCallable(instructorFunctions, 'resetUserPassword')({ userId: MEMBER_ID }),
    ).rejects.toThrow();
  });

  it('um aluno NÃO consegue repor a password de ninguém', async () => {
    await expect(
      httpsCallable(memberFunctions, 'resetUserPassword')({ userId: MEMBER_ID }),
    ).rejects.toThrow();
  });

  it('um Gestor NÃO alcança um utilizador de outro ginásio', async () => {
    // O `userId` vem do cliente; o `tenantId` vem sempre das claims.
    await expect(
      httpsCallable(managerFunctions, 'resetUserPassword')({
        userId: OTHER_TENANT_MEMBER_ID,
      }),
    ).rejects.toThrow();
  });

  it('um Gestor não repõe a sua própria password por esta via', async () => {
    await expect(
      httpsCallable(managerFunctions, 'resetUserPassword')({ userId: MANAGER_ID }),
    ).rejects.toThrow();
  });
});

describe('updateStaffRoles', () => {
  it('promove um Instrutor a Gestor, nas claims E no documento', async () => {
    await httpsCallable(managerFunctions, 'updateStaffRoles')({
      staffId: INSTRUCTOR_ID,
      roles: ['instructor', 'manager'],
    });

    // As claims são a autoridade real (é o que as Rules leem); o
    // documento é o que a UI lista. Escrever só num daria um Gestor que
    // a app mostra e o servidor recusa.
    const user = await adminAuth.getUser(INSTRUCTOR_ID);
    expect(user.customClaims?.roles).toEqual(['instructor', 'manager']);
    expect(user.customClaims?.tenantId).toBe(TENANT_ID);

    const staff = await adminFirestore
      .doc(`tenants/${TENANT_ID}/staff/${INSTRUCTOR_ID}`)
      .get();
    expect(staff.get('roles')).toEqual(['instructor', 'manager']);
  });

  it('um Gestor NÃO se despromove a si próprio', async () => {
    // Sem esta trava, o único Gestor de um ginásio consegue trancar-se
    // fora e fica a precisar de um developer — o oposto do objetivo.
    await expect(
      httpsCallable(managerFunctions, 'updateStaffRoles')({
        staffId: MANAGER_ID,
        roles: ['instructor'],
      }),
    ).rejects.toThrow();
  });

  it('mas PODE despromover outro Gestor', async () => {
    await httpsCallable(managerFunctions, 'updateStaffRoles')({
      staffId: SECOND_MANAGER_ID,
      roles: ['instructor'],
    });
    const user = await adminAuth.getUser(SECOND_MANAGER_ID);
    expect(user.customClaims?.roles).toEqual(['instructor']);
  });

  it('recusa deixar staff sem papel nenhum', async () => {
    await expect(
      httpsCallable(managerFunctions, 'updateStaffRoles')({
        staffId: INSTRUCTOR_ID,
        roles: [],
      }),
    ).rejects.toThrow();
  });
});

describe('updateSubscriptionStatus', () => {
  const SUBSCRIPTION_ID = 'subscription_powers_test';

  beforeAll(async () => {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/${SUBSCRIPTION_ID}`)
      .set({
        memberId: MEMBER_ID,
        planId: 'plan_standard',
        status: 'active',
        agreedPrice: 45,
        currency: 'EUR',
        activeServiceIds: ['service_sala'],
        startDate: new Date(),
      });
  });

  it('cancelar marca o estado e a data de fim', async () => {
    await httpsCallable(managerFunctions, 'updateSubscriptionStatus')({
      subscriptionId: SUBSCRIPTION_ID,
      status: 'cancelled',
    });

    const snapshot = await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/${SUBSCRIPTION_ID}`)
      .get();
    expect(snapshot.get('status')).toBe('cancelled');
    expect(snapshot.get('endedAt')).toBeTruthy();
    expect(snapshot.get('statusUpdatedBy')).toBe(MANAGER_ID);
  });

  it('reativar limpa a data de fim', async () => {
    // Sem isto, uma subscrição reativada ficava "ativa mas terminada em
    // X" — um estado contraditório que qualquer relatório leria mal.
    await httpsCallable(managerFunctions, 'updateSubscriptionStatus')({
      subscriptionId: SUBSCRIPTION_ID,
      status: 'active',
    });

    const snapshot = await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/${SUBSCRIPTION_ID}`)
      .get();
    expect(snapshot.get('status')).toBe('active');
    expect(snapshot.get('endedAt')).toBeUndefined();
  });

  it('um aluno NÃO consegue mexer no seu próprio plano', async () => {
    await expect(
      httpsCallable(memberFunctions, 'updateSubscriptionStatus')({
        subscriptionId: SUBSCRIPTION_ID,
        status: 'cancelled',
      }),
    ).rejects.toThrow();
  });

  it('recusa um estado que não existe', async () => {
    await expect(
      httpsCallable(managerFunctions, 'updateSubscriptionStatus')({
        subscriptionId: SUBSCRIPTION_ID,
        status: 'gratis',
      }),
    ).rejects.toThrow();
  });
});
