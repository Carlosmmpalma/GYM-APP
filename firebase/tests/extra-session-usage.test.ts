// Fase 8 (varredura de performance/bugs) — regressão para um bug REAL
// apanhado ao rever o código depois de tornar `isExtra` funcional.
//
// O bug: uma sessão marcada como EXTRA (UC08-A) nunca incrementa
// `usage` — é esse o objetivo, isenta o membro do limite semanal do
// plano. Mas os caminhos de CANCELAMENTO (`cancelBooking.ts`,
// `lib/bookingLogic.ts#prepareRelease`, `cancelFreeTrainingBooking.ts`)
// decrementavam `usage` a partir do `serviceId`/`period` do booking
// sem olhar ao `isExtra`. Resultado: marcar 1 sessão normal (usage 1/2)
// + 1 extra (continua 1/2) e depois cancelar a EXTRA deixava o usage a
// 0/2 — o membro recuperava uma utilização que nunca tinha gasto.
//
// Enquanto `isExtra` foi sempre `false` (até à Fase 8) este caminho
// não podia estar errado, e por isso ninguém tinha reparado.
//
// Precisa dos emuladores Firestore + Functions + Auth e de
// `firebase/functions` compilado. Ver `booking-concurrency.test.ts`.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import {
  FieldValue,
  Timestamp,
  getFirestore as getAdminFirestore,
} from 'firebase-admin/firestore';
import { deleteApp, initializeApp as initializeClientApp, type FirebaseApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_extra_usage_test';
const SERVICE_ID = 'service_pt';
const PLAN_ID = 'plan_plus';
const MEMBER_ID = 'member_extra_test';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-extra-usage-test');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFunctions: Functions;
let memberFunctions: Functions;

async function signedInFunctionsClient(
  appName: string,
  uid: string,
  claims: { tenantId: string; roles: string[] },
): Promise<Functions> {
  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-api-key' }, appName);
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

/** Uma ocorrência nova, sempre no futuro, com capacidade folgada. */
async function createOccurrence(id: string, hoursFromNow: number) {
  const start = new Date(Date.now() + hoursFromNow * 60 * 60 * 1000);
  await adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/${id}`).set({
    serviceId: SERVICE_ID,
    startAt: Timestamp.fromDate(start),
    endAt: Timestamp.fromDate(new Date(start.getTime() + 60 * 60 * 1000)),
    capacity: 10,
    status: 'scheduled',
    activeBookingCount: 0,
  });
}

async function usedThisPeriod(): Promise<number> {
  const snap = await adminFirestore
    .collection(`tenants/${TENANT_ID}/usage`)
    .where('memberId', '==', MEMBER_ID)
    .get();
  return snap.docs.reduce((total, doc) => total + ((doc.data().used as number) ?? 0), 0);
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));

  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Tenant extra/usage' });
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`).set({
    name: 'PT',
    active: true,
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`).set({
    name: 'Membro de teste',
    memberNumber: '000001',
    status: 'active',
  });
  // Plano LIMITADO — sem limite não haveria documento de `usage`
  // nenhum e o bug não seria observável.
  await adminFirestore.doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}`).set({
    name: 'Plus',
    active: true,
  });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}/services/${SERVICE_ID}`)
    .set({ enabled: true, usage: { type: 'limited', limit: 2, period: 'week' } });
  await adminFirestore.doc(`tenants/${TENANT_ID}/subscriptions/sub_1`).set({
    memberId: MEMBER_ID,
    planId: PLAN_ID,
    status: 'active',
    startDate: FieldValue.serverTimestamp(),
    agreedPrice: 0,
    currency: 'EUR',
    activeServiceIds: [SERVICE_ID],
  });

  managerFunctions = await signedInFunctionsClient('client-manager-extra', 'manager_1', {
    tenantId: TENANT_ID,
    roles: ['manager'],
  });
  memberFunctions = await signedInFunctionsClient('client-member-extra', MEMBER_ID, {
    tenantId: TENANT_ID,
    roles: ['member'],
  });
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

describe('UC08-A — sessão extra e o limite semanal (Fase 8, regressão)', () => {
  it('atribuir uma sessão EXTRA não consome utilização; cancelá-la não devolve nenhuma', async () => {
    await createOccurrence('occ_normal', 48);
    await createOccurrence('occ_extra', 72);

    // 1. Marcação NORMAL do próprio membro — consome 1 utilização.
    await httpsCallable(memberFunctions, 'createBooking')({
      occurrenceId: 'occ_normal',
      memberId: MEMBER_ID,
    });
    expect(await usedThisPeriod()).toBe(1);

    // 2. Sessão EXTRA atribuída pelo estúdio — NÃO consome.
    const assign = await httpsCallable(managerFunctions, 'assignMembersToOccurrence')({
      occurrenceId: 'occ_extra',
      memberIds: [MEMBER_ID],
      isExtra: true,
    });
    expect((assign.data as { results: { ok: boolean }[] }).results[0].ok).toBe(true);
    expect(await usedThisPeriod()).toBe(1);

    // 3. O ESTÚDIO cancela a sessão extra (`prepareRelease`). O usage
    //    tem de ficar em 1 — antes da correção descia para 0.
    await httpsCallable(managerFunctions, 'cancelOccurrenceForStudio')({
      occurrenceId: 'occ_extra',
    });
    expect(await usedThisPeriod()).toBe(1);
  }, 30_000);

  it('o próprio membro cancelar uma sessão EXTRA também não devolve utilização', async () => {
    await createOccurrence('occ_extra_self', 96);

    const before = await usedThisPeriod();

    await httpsCallable(managerFunctions, 'assignMembersToOccurrence')({
      occurrenceId: 'occ_extra_self',
      memberIds: [MEMBER_ID],
      isExtra: true,
    });
    expect(await usedThisPeriod()).toBe(before);

    // `cancelBooking.ts` — o caminho do próprio membro.
    await httpsCallable(memberFunctions, 'cancelBooking')({
      occurrenceId: 'occ_extra_self',
      memberId: MEMBER_ID,
    });
    expect(await usedThisPeriod()).toBe(before);
  }, 30_000);

  it('remarcar uma sessão EXTRA mantém-na extra no destino', async () => {
    await createOccurrence('occ_extra_from', 120);
    await createOccurrence('occ_extra_to', 144);

    const before = await usedThisPeriod();

    await httpsCallable(managerFunctions, 'assignMembersToOccurrence')({
      occurrenceId: 'occ_extra_from',
      memberIds: [MEMBER_ID],
      isExtra: true,
    });
    expect(await usedThisPeriod()).toBe(before);

    await httpsCallable(managerFunctions, 'rescheduleBooking')({
      fromOccurrenceId: 'occ_extra_from',
      toOccurrenceId: 'occ_extra_to',
      memberId: MEMBER_ID,
    });

    // Sem a correção, o destino nascia com `isExtra: false` e passava a
    // consumir uma utilização — o membro perdia uma sessão do plano só
    // por ter sido mudado de horário pelo estúdio.
    expect(await usedThisPeriod()).toBe(before);
    const moved = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_extra_to/bookings/${MEMBER_ID}`)
      .get();
    expect(moved.data()?.isExtra).toBe(true);
  }, 30_000);

  it('cancelar uma sessão NORMAL continua a devolver a utilização', async () => {
    // Prova que a correção não desligou o comportamento correto —
    // sem isto, um `usageRef = null` sempre passaria os dois testes
    // acima e partiria o UC10 inteiro.
    const before = await usedThisPeriod();
    expect(before).toBeGreaterThan(0);

    await httpsCallable(memberFunctions, 'cancelBooking')({
      occurrenceId: 'occ_normal',
      memberId: MEMBER_ID,
    });
    expect(await usedThisPeriod()).toBe(before - 1);
  }, 30_000);
});
