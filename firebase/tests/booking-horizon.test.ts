// O horizonte de marcação: com quantos dias de antecedência um aluno
// pode marcar.
//
// As séries geram ocorrências com 8 semanas de antecedência para o
// estúdio poder planear, e o aluno via-as todas — dois meses de horário
// para uma decisão que é sobre esta semana ou a próxima. E marcar com
// dois meses de antecedência ocupa uma vaga que mais ninguém pode usar,
// para uma aula de que já não se vai lembrar.
//
// Testado no SERVIDOR e não só no ecrã porque a diferença importa: o
// ecrã esconde as aulas fora do horizonte, mas esconder não é impedir.
// Um pedido direto à função continuaria a passar.
//
// Vive em `config/bookingPolicy`, ao lado de `minBookingNoticeMinutes`
// — são as duas pontas da mesma janela: não marcar demasiado em cima da
// hora, nem demasiado longe.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore, Timestamp } from 'firebase-admin/firestore';
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
const TENANT_ID = 'tenant_horizon';
const MEMBER_ID = 'member_horizon';
const SERVICE_ID = 'service_horizon';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-horizon');
const adminFirestore = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);

const clientApps: FirebaseApp[] = [];
let memberFunctions: Functions;

async function signedInFunctionsClient(
  name: string,
  uid: string,
  claims: Record<string, unknown>,
): Promise<Functions> {
  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-key' }, name);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  const token = await adminAuth.createCustomToken(uid, claims);
  await signInWithCustomToken(auth, token);
  const functions = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return functions;
}

/** Uma aula daqui a `dias`, com uma hora de duração. */
async function criarAula(id: string, dias: number): Promise<void> {
  const inicio = new Date();
  inicio.setDate(inicio.getDate() + dias);
  inicio.setHours(10, 0, 0, 0);
  const fim = new Date(inicio.getTime() + 60 * 60 * 1000);

  await adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/${id}`).set({
    serviceId: SERVICE_ID,
    startAt: Timestamp.fromDate(inicio),
    endAt: Timestamp.fromDate(fim),
    capacity: 10,
    status: 'scheduled',
    activeBookingCount: 0,
  });
}

beforeAll(async () => {
  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`).set({
    name: 'Membro do horizonte',
    memberNumber: '000900',
    status: 'active',
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`).set({
    name: 'Aulas de grupo',
    active: true,
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/plans/plan_horizon`).set({
    name: 'Ilimitado',
    active: true,
    currentPrice: 40,
    currency: 'EUR',
  });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/plan_horizon/services/${SERVICE_ID}`)
    .set({ enabled: true, usage: { type: 'unlimited' } });
  await adminFirestore.doc(`tenants/${TENANT_ID}/subscriptions/sub_horizon`).set({
    memberId: MEMBER_ID,
    planId: 'plan_horizon',
    status: 'active',
    startDate: Timestamp.now(),
    endDate: null,
    agreedPrice: 40,
    currency: 'EUR',
    activeServiceIds: [SERVICE_ID],
  });

  // Sete dias de horizonte.
  await adminFirestore.doc(`tenants/${TENANT_ID}/config/bookingPolicy`).set({
    bookingHorizonDays: 7,
    minBookingNoticeMinutes: 0,
  });

  await criarAula('occ_amanha', 1);
  await criarAula('occ_daqui_a_um_mes', 30);

  memberFunctions = await signedInFunctionsClient('client-member-horizon', MEMBER_ID, {
    tenantId: TENANT_ID,
    roles: ['member'],
  });
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

describe('createBooking — horizonte de marcação', () => {
  it('dentro do horizonte, marca', async () => {
    const result = await httpsCallable(memberFunctions, 'createBooking')({
      occurrenceId: 'occ_amanha',
      memberId: MEMBER_ID,
    });
    expect(result.data).toBeTruthy();
  }, 15_000);

  it('para lá do horizonte, recusa — e diz o limite', async () => {
    await expect(
      httpsCallable(memberFunctions, 'createBooking')({
        occurrenceId: 'occ_daqui_a_um_mes',
        memberId: MEMBER_ID,
      }),
    ).rejects.toMatchObject({
      code: 'functions/failed-precondition',
      details: { reason: 'beyond-horizon', horizonDays: 7 },
    });
  }, 15_000);

  it('sem horizonte definido (0), volta a aceitar tudo', async () => {
    // `0` é o valor por omissão, para não mudar o comportamento de um
    // estúdio que já usa a app sem saber desta definição.
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/config/bookingPolicy`)
      .set({ bookingHorizonDays: 0 }, { merge: true });

    const result = await httpsCallable(memberFunctions, 'createBooking')({
      occurrenceId: 'occ_daqui_a_um_mes',
      memberId: MEMBER_ID,
    });
    expect(result.data).toBeTruthy();
  }, 15_000);
});
