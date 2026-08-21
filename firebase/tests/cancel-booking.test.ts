// Fase 11 (bug reportado: "se cancelar aulas tmb n cancela") — o
// caminho completo de marcar e cancelar uma aula, contra o servidor a
// sério.
//
// Não havia teste dedicado ao cancelamento pelo próprio membro: o
// `extra-session-usage.test.ts` chama-o, mas para verificar outra coisa
// (a utilização semanal). Este verifica o que se espera de fora: a
// marcação deixa de estar ativa, a vaga volta, e cancelar duas vezes
// falha em vez de descontar duas.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import {
  getFirestore as getAdminFirestore,
  Timestamp,
} from 'firebase-admin/firestore';
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
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_cancel_test';
const MEMBER_ID = 'cancel_member';
const SERVICE_ID = 'service_aulas';
const PLAN_ID = 'plan_standard';
const OCCURRENCE_ID = 'occ_cancel';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-cancel');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let memberFunctions: Functions;

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`)
    .set({ name: 'Aulas', active: true });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}`)
    .set({ name: 'Standard', active: true });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}/services/${SERVICE_ID}`)
    .set({ enabled: true, usage: { type: 'unlimited' } });
  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`).set({
    name: 'Aluno',
    memberNumber: '000001',
    status: 'active',
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/subscriptions/sub_1`).set({
    memberId: MEMBER_ID,
    planId: PLAN_ID,
    status: 'active',
    agreedPrice: 40,
    currency: 'EUR',
    activeServiceIds: [SERVICE_ID],
    startDate: new Date(),
  });

  await adminAuth
    .createUser({ uid: MEMBER_ID, email: `${MEMBER_ID}@example.test`, password: 'TestPass123!' })
    .catch(() => undefined);

  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    'cancel-member',
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(MEMBER_ID, {
      tenantId: TENANT_ID,
      roles: ['member'],
    }),
  );
  memberFunctions = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(memberFunctions, 'localhost', 5001);
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

beforeEach(async () => {
  // Sessão nova a cada teste: daqui a dois dias, com duas vagas.
  const start = new Date(Date.now() + 48 * 60 * 60 * 1000);
  await adminFirestore
    .recursiveDelete(
      adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`),
    );
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
    .set({
      serviceId: SERVICE_ID,
      startAt: Timestamp.fromDate(start),
      endAt: Timestamp.fromDate(new Date(start.getTime() + 3600_000)),
      capacity: 2,
      status: 'scheduled',
      activeBookingCount: 0,
    });
});

async function occurrence() {
  return adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
    .get();
}

async function booking() {
  return adminFirestore
    .doc(
      `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}/bookings/${MEMBER_ID}`,
    )
    .get();
}

describe('Marcar e cancelar uma aula', () => {
  it('cancelar liberta a vaga e marca a reserva como cancelada',
    async () => {
      await httpsCallable(memberFunctions, 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: MEMBER_ID,
      });

      expect((await occurrence()).get('activeBookingCount')).toBe(1);
      expect((await booking()).get('status')).toBe('booked');

      await httpsCallable(memberFunctions, 'cancelBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: MEMBER_ID,
      });

      // As duas coisas que o utilizador vê: a marcação sai da lista dele
      // e a vaga volta a ficar disponível para outra pessoa.
      expect((await booking()).get('status')).toBe('cancelled');
      expect((await occurrence()).get('activeBookingCount')).toBe(0);
    });

  it('cancelar duas vezes falha à segunda — não desconta duas vagas',
    async () => {
      await httpsCallable(memberFunctions, 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: MEMBER_ID,
      });
      await httpsCallable(memberFunctions, 'cancelBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: MEMBER_ID,
      });

      await expect(
        httpsCallable(memberFunctions, 'cancelBooking')({
          occurrenceId: OCCURRENCE_ID,
          // Sem isto o teste passava pela razao ERRADA: falhava por
          // faltar o parametro, nao por a marcacao ja estar cancelada.
          memberId: MEMBER_ID,
        }),
      ).rejects.toThrow();

      // O contador não pode ir a negativo por se carregar duas vezes.
      expect((await occurrence()).get('activeBookingCount')).toBe(0);
    });

  it('cancelar sem ter marcado falha', async () => {
    await expect(
      httpsCallable(memberFunctions, 'cancelBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: MEMBER_ID,
      }),
    ).rejects.toThrow();
  });

  it('depois de cancelar dá para marcar outra vez', async () => {
    // O caso real de quem cancela por engano.
    await httpsCallable(memberFunctions, 'createBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: MEMBER_ID,
    });
    await httpsCallable(memberFunctions, 'cancelBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: MEMBER_ID,
    });
    await httpsCallable(memberFunctions, 'createBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: MEMBER_ID,
    });

    expect((await booking()).get('status')).toBe('booked');
    expect((await occurrence()).get('activeBookingCount')).toBe(1);
  });
});
