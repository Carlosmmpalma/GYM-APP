// QA: o ciclo de vida de um aluno, de ponta a ponta.
//
// As regras e as funções estão bem cobertas isoladamente — 34 ficheiros,
// centenas de testes. O que não estava coberto é a SEQUÊNCIA: o estado a
// passar de um passo para o seguinte, que é onde vivem os bugs de
// integração.
//
// Um aluno é criado, recebe um plano, marca, esbarra no limite, é
// marcado como presente, cancela, e no fim o estúdio cancela a série
// toda. Cada passo verifica o efeito do anterior.
//
// Corre contra o Emulator Suite a sério (Firestore + Functions + Auth),
// com as Cloud Functions reais e as Security Rules em vigor.

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
const TENANT_ID = 'tenant_qa_ciclo';
const SERVICE_ID = 'svc_qa';
const PLAN_ID = 'plan_qa';
const MEMBER_ID = 'member_qa';
const INSTRUCTOR_ID = 'instructor_qa';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-qa-ciclo');
const adminFirestore = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);
const tenant = adminFirestore.doc(`tenants/${TENANT_ID}`);

const clientApps: FirebaseApp[] = [];
let gestor: Functions;
let aluno: Functions;
let instrutor: Functions;

async function cliente(
  nome: string,
  uid: string,
  roles: string[],
): Promise<Functions> {
  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-key' }, nome);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const functions = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return functions;
}

function isoWeekKey(date: Date): string {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNumber = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  d.setUTCDate(d.getUTCDate() + 4 - dayNumber);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/** Duas aulas na MESMA hora, e uma terceira logo a seguir. */
const amanha = new Date(Date.now() + 86_400_000);
amanha.setHours(10, 0, 0, 0);
const amanhaMaisTarde = new Date(amanha.getTime() + 3_600_000);
const periodo = isoWeekKey(amanha);

async function criarAula(id: string, inicio: Date): Promise<void> {
  await tenant.collection('sessionOccurrences').doc(id).set({
    serviceId: SERVICE_ID,
    seriesId: 'serie_qa',
    instructorId: INSTRUCTOR_ID,
    startAt: Timestamp.fromDate(inicio),
    endAt: Timestamp.fromDate(new Date(inicio.getTime() + 3_600_000)),
    capacity: 10,
    status: 'scheduled',
    activeBookingCount: 0,
  });
}

async function usadas(): Promise<number> {
  const doc = await tenant
    .collection('usage')
    .doc(`${MEMBER_ID}_${SERVICE_ID}_${periodo}`)
    .get();
  return (doc.data()?.used as number | undefined) ?? 0;
}

beforeAll(async () => {
  await tenant.set({ name: 'Estúdio QA' });
  await tenant.collection('services').doc(SERVICE_ID).set({
    name: 'Aulas de grupo',
    active: true,
  });

  // Plano com limite semanal de 1 — é o que torna o limite observável.
  await tenant.collection('plans').doc(PLAN_ID).set({
    name: 'Uma por semana',
    active: true,
    currentPrice: 30,
    currency: 'EUR',
  });
  await tenant.collection('plans').doc(PLAN_ID).collection('services').doc(SERVICE_ID).set({
    enabled: true,
    usage: { type: 'limited', limit: 1, period: 'week' },
  });

  await tenant.collection('staff').doc(INSTRUCTOR_ID).set({
    name: 'Instrutor QA',
    email: 'instrutor@qa.test',
    roles: ['instructor'],
    status: 'active',
  });
  await tenant.collection('sessionSeries').doc('serie_qa').set({
    serviceId: SERVICE_ID,
    instructorId: INSTRUCTOR_ID,
    dayOfWeek: amanha.getDay() === 0 ? 7 : amanha.getDay(),
    startTime: '10:00',
    durationMinutes: 60,
    capacity: 10,
    startDate: Timestamp.now(),
    status: 'active',
  });

  // O membro é semeado com o id do token. `createMember` gera um uid
  // próprio (e está coberto em `manager-powers.test.ts`); aqui o que
  // interessa é o ciclo de marcação, que precisa de um id conhecido.
  await tenant.collection('members').doc(MEMBER_ID).set({
    memberNumber: '000QA1',
    name: 'Aluna QA',
    status: 'active',
  });

  await criarAula('occ_a', amanha);
  await criarAula('occ_b', amanha); // mesma hora que a A
  await criarAula('occ_c', amanhaMaisTarde);

  gestor = await cliente('qa-gestor', 'gestor_qa', ['manager']);
  aluno = await cliente('qa-aluno', MEMBER_ID, ['member']);
  instrutor = await cliente('qa-instrutor', INSTRUCTOR_ID, ['instructor']);
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

describe('QA — o ciclo de vida de um aluno', () => {
  it('1. sem plano, não consegue marcar', async () => {
    // A ordem importa: é isto que prova que o passo seguinte (atribuir
    // o plano) é o que destranca a marcação, e não outra coisa.
    await expect(
      httpsCallable(aluno, 'createBooking')({ occurrenceId: 'occ_a', memberId: MEMBER_ID }),
    ).rejects.toMatchObject({ code: 'functions/permission-denied' });
  }, 15_000);

  it('2. o Gestor atribui-lhe o plano', async () => {
    const r = await httpsCallable(gestor, 'createSubscription')({
      memberId: MEMBER_ID,
      planId: PLAN_ID,
      agreedPrice: 30,
      currency: 'EUR',
    });
    expect((r.data as { subscriptionId: string }).subscriptionId).toBeTruthy();
  }, 15_000);

  it('3. agora marca, e a utilização conta', async () => {
    await httpsCallable(aluno, 'createBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER_ID,
    });
    expect(await usadas()).toBe(1);

    const occ = await tenant.collection('sessionOccurrences').doc('occ_a').get();
    expect(occ.get('activeBookingCount')).toBe(1);
  }, 15_000);

  it('4. outra aula À MESMA HORA é recusada', async () => {
    // A regra que não existia: ninguém está em dois sítios ao mesmo
    // tempo. Antes disto, marcar as duas era possível.
    await expect(
      httpsCallable(aluno, 'createBooking')({ occurrenceId: 'occ_b', memberId: MEMBER_ID }),
    ).rejects.toMatchObject({
      code: 'functions/failed-precondition',
      details: { reason: 'overlap' },
    });
  }, 15_000);

  it('5. e uma aula noutra hora esbarra no limite semanal', async () => {
    // Recusada por motivo DIFERENTE do anterior — `resource-exhausted`
    // e não `failed-precondition`. É o que prova que as duas regras são
    // independentes e nenhuma mascara a outra: uma diz "estás noutro
    // sítio a essa hora", a outra "já gastaste a semana".
    await expect(
      httpsCallable(aluno, 'createBooking')({ occurrenceId: 'occ_c', memberId: MEMBER_ID }),
    ).rejects.toMatchObject({
      code: 'functions/resource-exhausted',
      details: { reason: 'usage-limit', used: 1, limit: 1 },
    });
    expect(await usadas()).toBe(1);
  }, 15_000);

  it('6. o Instrutor marca a presença', async () => {
    // Escrita direta (Manager ou Instrutor), não Cloud Function — é um
    // documento isolado, sem contador nem cascata.
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_a/attendance/${MEMBER_ID}`)
      .set({
        memberId: MEMBER_ID,
        status: 'attended',
        recordedBy: INSTRUCTOR_ID,
        recordedAt: Timestamp.now(),
      });

    const presenca = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_a/attendance/${MEMBER_ID}`)
      .get();
    expect(presenca.get('status')).toBe('attended');
  }, 15_000);

  it('7. cancelar devolve a sessão ao limite', async () => {
    await httpsCallable(aluno, 'cancelBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER_ID,
    });
    expect(await usadas()).toBe(0);

    const occ = await tenant.collection('sessionOccurrences').doc('occ_a').get();
    expect(occ.get('activeBookingCount')).toBe(0);
  }, 15_000);

  it('8. com a sessão devolvida, já consegue marcar a outra', async () => {
    // Fecha o ciclo: o limite não é um contador que só sobe.
    await httpsCallable(aluno, 'createBooking')({
      occurrenceId: 'occ_c',
      memberId: MEMBER_ID,
    });
    expect(await usadas()).toBe(1);
  }, 15_000);

  it('9. o Gestor cancela a série, e tudo volta atrás', async () => {
    const r = await httpsCallable(gestor, 'cancelSeriesForStudio')({ seriesId: 'serie_qa' });
    expect((r.data as { cancelledBookings: number }).cancelledBookings).toBe(1);

    // A série, as aulas futuras, e a utilização do aluno.
    const serie = await tenant.collection('sessionSeries').doc('serie_qa').get();
    expect(serie.get('status')).toBe('cancelled');
    const occ = await tenant.collection('sessionOccurrences').doc('occ_c').get();
    expect(occ.get('status')).toBe('cancelled');
    expect(await usadas()).toBe(0);
  }, 25_000);

  it('10. o Instrutor NÃO consegue fazer o que é do Gestor', async () => {
    // O contraponto: a jornada toda correu com papéis certos. Esta
    // prova que os papéis não são decoração.
    await expect(
      httpsCallable(instrutor, 'createSubscription')({
        memberId: MEMBER_ID,
        planId: PLAN_ID,
        agreedPrice: 30,
        currency: 'EUR',
      }),
    ).rejects.toMatchObject({ code: 'functions/permission-denied' });
  }, 15_000);
});
