// Fase 11 — lembrete antes da aula.
//
// A falta sem aviso é o custo real de um estúdio com capacidade
// limitada: o lugar ficou ocupado e ninguém o pôde usar. O lembrete
// existe tanto para quem vem confirmar como para quem já não pode vir
// cancelar a tempo.
//
// O que aqui se prova não é a entrega da notificação (isso depende de
// tokens FCM e de configuração que ainda não existe — ver LANCAMENTO.md)
// mas as decisões que geram o envio: que sessões entram na janela, e
// que a mesma sessão nunca é avisada duas vezes.

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
const TENANT_ID = 'tenant_reminders_test';
const SERVICE_ID = 'service_aulas';
const MANAGER = 'rem_gestor';
const MEMBER = 'rem_aluno';
const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-reminders');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFns: Functions;
let memberFns: Functions;

async function clientFor(uid: string, roles: string[]) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    `rem-${uid}`,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const fns = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(fns, 'localhost', 5001);
  return fns;
}

function hoursFromNow(hours: number) {
  return new Date(Date.now() + hours * 3600_000);
}

/** Cria uma sessão daqui a `hours` horas, com o aluno inscrito. */
async function createOccurrence(id: string, hours: number) {
  const start = hoursFromNow(hours);
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${id}`)
    .set({
      serviceId: SERVICE_ID,
      startAt: Timestamp.fromDate(start),
      endAt: Timestamp.fromDate(new Date(start.getTime() + 3600_000)),
      capacity: 10,
      status: 'scheduled',
      activeBookingCount: 1,
    });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${id}/bookings/${MEMBER}`)
    .set({
      memberId: MEMBER,
      status: 'booked',
      source: 'self',
      isExtra: false,
      serviceId: SERVICE_ID,
      createdAt: Timestamp.now(),
    });
}

async function reminderSentAt(id: string) {
  const doc = await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${id}`)
    .get();
  return doc.get('reminderSentAt') ?? null;
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`)
    .set({ name: 'Aulas', active: true });
  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER}`).set({
    name: 'Aluno',
    memberNumber: '000001',
    status: 'active',
  });

  for (const uid of [MANAGER, MEMBER]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }
  managerFns = await clientFor(MANAGER, ['manager']);
  memberFns = await clientFor(MEMBER, ['member']);
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

beforeEach(async () => {
  const existing = await adminFirestore
    .collection(`tenants/${TENANT_ID}/sessionOccurrences`)
    .get();
  await Promise.all(
    existing.docs.map((doc) => adminFirestore.recursiveDelete(doc.ref)),
  );
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/config/notificationPolicy`)
    .delete();
});

describe('Que sessões entram no lembrete', () => {
  it('uma sessão dentro da janela é avisada', async () => {
    await createOccurrence('occ_proxima', 3);
    const result = await httpsCallable(managerFns, 'sendSessionRemindersNow')({});

    expect((result.data as { notified: number }).notified).toBe(1);
    expect(await reminderSentAt('occ_proxima')).not.toBeNull();
  }, 30_000);

  it('uma sessão para lá da janela ainda NÃO é avisada', async () => {
    // Por omissão avisa-se 12h antes. Uma aula marcada para daqui a
    // três dias não interessa hoje — o lembrete só serve se chegar
    // perto o suficiente para mudar o comportamento.
    await createOccurrence('occ_longe', 72);
    await httpsCallable(managerFns, 'sendSessionRemindersNow')({});

    expect(await reminderSentAt('occ_longe')).toBeNull();
  }, 30_000);

  it('uma sessão CANCELADA não é avisada', async () => {
    await createOccurrence('occ_cancelada', 3);
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_cancelada`)
      .update({ status: 'cancelled' });

    await httpsCallable(managerFns, 'sendSessionRemindersNow')({});
    expect(await reminderSentAt('occ_cancelada')).toBeNull();
  }, 30_000);

  it('a antecedência é configurável pelo estúdio', async () => {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/config/notificationPolicy`)
      .set({ sessionReminderHours: 96 });
    await createOccurrence('occ_longe', 72);

    await httpsCallable(managerFns, 'sendSessionRemindersNow')({});
    expect(await reminderSentAt('occ_longe')).not.toBeNull();
  }, 30_000);

  it('o estúdio pode desligar os lembretes', async () => {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/config/notificationPolicy`)
      .set({ sessionRemindersEnabled: false });
    await createOccurrence('occ_proxima', 3);

    await httpsCallable(managerFns, 'sendSessionRemindersNow')({});
    expect(await reminderSentAt('occ_proxima')).toBeNull();
  }, 30_000);
});

describe('Nunca avisa duas vezes', () => {
  it('a segunda passagem não volta a avisar a mesma sessão', async () => {
    // A função corre de hora a hora e a mesma sessão fica na janela
    // várias vezes seguidas — é `reminderSentAt` que garante um único
    // aviso, não a janela.
    await createOccurrence('occ_proxima', 3);
    await httpsCallable(managerFns, 'sendSessionRemindersNow')({});
    const primeiro = await reminderSentAt('occ_proxima');

    const segunda = await httpsCallable(managerFns, 'sendSessionRemindersNow')({});
    expect((segunda.data as { notified: number }).notified).toBe(0);
    expect(await reminderSentAt('occ_proxima')).toEqual(primeiro);
  }, 30_000);

  it('uma sessão sem inscritos também fica marcada', async () => {
    // Senão era relida a cada hora até começar, sem nunca haver nada
    // para enviar.
    await createOccurrence('occ_vazia', 3);
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_vazia/bookings/${MEMBER}`)
      .delete();

    const result = await httpsCallable(managerFns, 'sendSessionRemindersNow')({});
    expect((result.data as { notified: number }).notified).toBe(0);
    expect(await reminderSentAt('occ_vazia')).not.toBeNull();
  }, 30_000);
});

describe('Quem pode forçar o envio', () => {
  it('um aluno não consegue', async () => {
    await expect(
      httpsCallable(memberFns, 'sendSessionRemindersNow')({}),
    ).rejects.toThrow();
  }, 30_000);
});
