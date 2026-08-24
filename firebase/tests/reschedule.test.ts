// Última ronda — remarcar um aluno não pode deixá-lo sem nada.
//
// `rescheduleBooking` cancela na origem e marca no destino. Como são
// duas ocorrências diferentes, não há transação que junte as duas — e
// a versão anterior largava a origem PRIMEIRO e só depois descobria
// que o destino estava cheio, cancelado, inexistente, ou fora do plano
// do aluno. O instrutor carregava num botão para mudar alguém de hora
// e o aluno saía do horário.
//
// O que se prova aqui: os casos que se conseguem saber de antemão
// recusam antes de tocar em nada, e a marcação de origem fica intacta.

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
const TENANT_ID = 'tenant_reschedule_test';
const SERVICE_AULAS = 'service_aulas';
const SERVICE_PT = 'service_pt';
const PLAN_ID = 'plan_standard';
const FUNCTIONS_REGION = 'europe-west1';

const MANAGER = 'resched_gestor';
const ALUNO = 'resched_aluno';
/** Ocupa a vaga única da sessão de destino cheia. */
const OUTRO = 'resched_outro';

const FROM = 'occ_origem';
const TO = 'occ_destino';
const TO_PT = 'occ_destino_pt';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-resched');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
const fns: Record<string, Functions> = {};

async function clientFor(uid: string, roles: string[]) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    `resched-${uid}`,
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

async function createOccurrence(params: {
  id: string;
  serviceId: string;
  capacity: number;
  hours: number;
  status?: string;
}) {
  const start = new Date(Date.now() + params.hours * 3600_000);
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${params.id}`)
    .set({
      serviceId: params.serviceId,
      startAt: Timestamp.fromDate(start),
      endAt: Timestamp.fromDate(new Date(start.getTime() + 3600_000)),
      capacity: params.capacity,
      status: params.status ?? 'scheduled',
      activeBookingCount: 0,
    });
}

async function bookingStatus(occurrenceId: string, memberId: string) {
  const doc = await adminFirestore
    .doc(
      `tenants/${TENANT_ID}/sessionOccurrences/${occurrenceId}/bookings/${memberId}`,
    )
    .get();
  return doc.exists ? (doc.get('status') as string) : null;
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });

  for (const serviceId of [SERVICE_AULAS, SERVICE_PT]) {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/services/${serviceId}`)
      .set({ name: serviceId, active: true });
  }
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}`)
    .set({ name: 'Standard', active: true });
  // O plano dá aulas de grupo, mas NÃO dá PT.
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/plans/${PLAN_ID}/services/${SERVICE_AULAS}`)
    .set({ enabled: true, usage: { type: 'unlimited' } });

  for (const uid of [ALUNO, OUTRO]) {
    await adminFirestore.doc(`tenants/${TENANT_ID}/members/${uid}`).set({
      name: uid,
      memberNumber: uid,
      status: 'active',
    });
    await adminFirestore.doc(`tenants/${TENANT_ID}/subscriptions/sub_${uid}`).set({
      memberId: uid,
      planId: PLAN_ID,
      status: 'active',
      agreedPrice: 40,
      currency: 'EUR',
      activeServiceIds: [SERVICE_AULAS],
      startDate: Timestamp.now(),
    });
  }

  for (const uid of [MANAGER, ALUNO, OUTRO]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }
  fns[MANAGER] = await clientFor(MANAGER, ['manager']);
  fns[ALUNO] = await clientFor(ALUNO, ['member']);
  fns[OUTRO] = await clientFor(OUTRO, ['member']);
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

beforeEach(async () => {
  for (const id of [FROM, TO, TO_PT]) {
    await adminFirestore.recursiveDelete(
      adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/${id}`),
    );
  }
  await createOccurrence({ id: FROM, serviceId: SERVICE_AULAS, capacity: 5, hours: 48 });
  await createOccurrence({ id: TO, serviceId: SERVICE_AULAS, capacity: 1, hours: 72 });
  await createOccurrence({ id: TO_PT, serviceId: SERVICE_PT, capacity: 5, hours: 72 });

  // O aluno está marcado na origem — é isto que nunca se pode perder.
  await httpsCallable(fns[ALUNO], 'createBooking')({
    occurrenceId: FROM,
    memberId: ALUNO,
  });
});

async function reschedule(to: string) {
  return httpsCallable(fns[MANAGER], 'rescheduleBooking')({
    fromOccurrenceId: FROM,
    toOccurrenceId: to,
    memberId: ALUNO,
  });
}

describe('Remarcar com destino válido', () => {
  it('move a marcação e liberta a vaga na origem', async () => {
    await reschedule(TO);

    expect(await bookingStatus(TO, ALUNO)).toBe('booked');
    expect(await bookingStatus(FROM, ALUNO)).toBe('cancelled');

    const origem = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${FROM}`)
      .get();
    expect(origem.get('activeBookingCount')).toBe(0);
  }, 30_000);
});

describe('Destino impossível — a origem fica intacta', () => {
  it('destino cheio: recusa sem cancelar nada', async () => {
    await httpsCallable(fns[OUTRO], 'createBooking')({
      occurrenceId: TO,
      memberId: OUTRO,
    });

    await expect(reschedule(TO)).rejects.toThrow();

    // O que interessa: o aluno continua marcado onde estava.
    expect(await bookingStatus(FROM, ALUNO)).toBe('booked');
    expect(await bookingStatus(TO, ALUNO)).toBeNull();
  }, 30_000);

  it('destino de um serviço fora do plano: recusa sem cancelar nada',
    async () => {
      await expect(reschedule(TO_PT)).rejects.toThrow();
      expect(await bookingStatus(FROM, ALUNO)).toBe('booked');
    }, 30_000);

  it('destino cancelado: recusa sem cancelar nada', async () => {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${TO}`)
      .update({ status: 'cancelled' });

    await expect(reschedule(TO)).rejects.toThrow();
    expect(await bookingStatus(FROM, ALUNO)).toBe('booked');
  }, 30_000);

  it('destino inexistente: recusa sem cancelar nada', async () => {
    await expect(reschedule('occ_que_nao_existe')).rejects.toThrow();
    expect(await bookingStatus(FROM, ALUNO)).toBe('booked');
  }, 30_000);

  it('remarcar para a MESMA sessão é recusado', async () => {
    // Sem esta verificação, a origem era cancelada e a seguir marcada
    // outra vez — muito trabalho para não mudar nada, e uma janela em
    // que o aluno não estava em lado nenhum.
    await expect(reschedule(FROM)).rejects.toThrow();
    expect(await bookingStatus(FROM, ALUNO)).toBe('booked');
  }, 30_000);
});
