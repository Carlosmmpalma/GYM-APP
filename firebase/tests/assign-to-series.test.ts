// Atribuir alunos a uma série inteira — "todas as semanas".
//
// O pedido veio do estúdio: inscrever alguém numa aula que se repete
// obrigava a repetir o gesto semana a semana, e nas semanas ainda não
// geradas não havia sequer onde o fazer.
//
// Metade da peça já existia no servidor: a série tem
// `preAssignedMemberIds` e a geração semanal marca essas pessoas em
// cada aula nova. O que faltava era escrever nessa lista — e tratar
// das aulas JÁ geradas, que a lista não alcança porque já existem.
//
// É essa divisão que estes testes guardam: a lista (o futuro) e as
// ocorrências (o presente) têm de ficar as duas certas, e uma semana
// que falhe não pode levar as outras à frente.

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
const TENANT_ID = 'tenant_assign_series';
const SERVICE_ID = 'svc_as';
const PLAN_ID = 'plan_as';
const SERIES_ID = 'serie_as';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-assign-series');
const adminFirestore = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);
const tenant = adminFirestore.collection('tenants').doc(TENANT_ID);

const clientApps: FirebaseApp[] = [];
let gestor: Functions;

/** Quatro segundas-feiras seguidas, todas no futuro. */
const semanas = [0, 1, 2, 3].map((i) => {
  const d = new Date(Date.now() + (i + 1) * 7 * 86_400_000);
  d.setHours(18, 0, 0, 0);
  return d;
});

async function plano(memberId: string, limite?: number): Promise<void> {
  await tenant.collection('subscriptions').doc(`sub_${memberId}`).set({
    memberId,
    planId: PLAN_ID,
    status: 'active',
    activeServiceIds: [SERVICE_ID],
  });
  void limite;
}

async function marcacoesDe(memberId: string): Promise<number> {
  const snap = await adminFirestore
    .collectionGroup('bookings')
    .where('memberId', '==', memberId)
    .where('status', '==', 'booked')
    .get();
  return snap.docs.filter((d) => d.ref.path.includes(TENANT_ID)).length;
}

beforeAll(async () => {
  await tenant.set({ name: 'Estúdio da série' });
  await tenant.collection('services').doc(SERVICE_ID).set({ name: 'Hyrox', active: true });

  // Plano SEM limite: o que se mede aqui é o alcance da atribuição,
  // não o limitador — esse tem os seus testes.
  await tenant.collection('plans').doc(PLAN_ID).set({
    name: 'Ilimitado', active: true, currentPrice: 50, currency: 'EUR',
  });
  await tenant.collection('plans').doc(PLAN_ID).collection('services').doc(SERVICE_ID).set({
    enabled: true,
    usage: { type: 'unlimited' },
  });

  await tenant.collection('sessionSeries').doc(SERIES_ID).set({
    serviceId: SERVICE_ID,
    dayOfWeek: 1,
    startTime: '18:00',
    durationMinutes: 60,
    capacity: 10,
    startDate: Timestamp.now(),
    status: 'active',
    preAssignedMemberIds: [],
  });

  // Três das quatro semanas já geradas. A quarta fica por gerar de
  // propósito: é ela que prova que a lista cobre o futuro.
  for (let i = 0; i < 3; i += 1) {
    await tenant.collection('sessionOccurrences').doc(`occ_as_${i}`).set({
      serviceId: SERVICE_ID,
      seriesId: SERIES_ID,
      startAt: Timestamp.fromDate(semanas[i]),
      endAt: Timestamp.fromDate(new Date(semanas[i].getTime() + 3_600_000)),
      // A terceira nasce CHEIA: uma semana sem vaga não pode levar as
      // outras à frente.
      capacity: i === 2 ? 1 : 10,
      activeBookingCount: i === 2 ? 1 : 0,
      status: 'scheduled',
    });
  }

  for (const id of ['membro_as_1', 'membro_as_2', 'membro_sem_plano']) {
    await tenant.collection('members').doc(id).set({
      memberNumber: id, name: id, status: 'active',
    });
  }
  await plano('membro_as_1');
  await plano('membro_as_2');
  // `membro_sem_plano` fica sem subscrição, de propósito.

  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-key' }, 'as-gestor');
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken('gestor_as', { tenantId: TENANT_ID, roles: ['manager'] }),
  );
  gestor = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(gestor, 'localhost', 5001);
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

describe('assignMembersToSeries', () => {
  it('marca nas aulas já geradas E entra na lista da série', async () => {
    const r = await httpsCallable(gestor, 'assignMembersToSeries')({
      seriesId: SERIES_ID,
      memberIds: ['membro_as_1'],
    });
    const data = r.data as {
      occurrences: number;
      results: Record<string, { assigned: number; skipped: number }>;
    };

    // Três geradas: duas com vaga, uma cheia.
    expect(data.occurrences).toBe(3);
    expect(data.results.membro_as_1.assigned).toBe(2);
    expect(data.results.membro_as_1.skipped).toBe(1);

    expect(await marcacoesDe('membro_as_1')).toBe(2);

    // E a lista, que é o que cobre as semanas por gerar.
    const serie = await tenant.collection('sessionSeries').doc(SERIES_ID).get();
    expect(serie.get('preAssignedMemberIds')).toContain('membro_as_1');
  }, 30_000);

  it('uma semana cheia não impede as outras', async () => {
    // O contraponto do teste de cima, dito explicitamente: a aula
    // `occ_as_2` nasceu com capacidade 1 e já ocupada. Se uma falha
    // abortasse o pedido, o membro anterior teria ficado com zero.
    expect(await marcacoesDe('membro_as_1')).toBeGreaterThan(0);
  }, 15_000);

  it('quem não tem plano fica de fora, e di-lo', async () => {
    const r = await httpsCallable(gestor, 'assignMembersToSeries')({
      seriesId: SERIES_ID,
      memberIds: ['membro_sem_plano'],
    });
    const data = r.data as {
      results: Record<string, { assigned: number; skipped: number }>;
    };

    expect(data.results.membro_sem_plano.assigned).toBe(0);
    expect(data.results.membro_sem_plano.skipped).toBe(3);
    expect(await marcacoesDe('membro_sem_plano')).toBe(0);
  }, 30_000);

  it('correr duas vezes não duplica nem rebenta', async () => {
    // O Gestor vai carregar duas vezes — por engano, ou por não ter a
    // certeza se a primeira pegou. O `arrayUnion` trata da lista; as
    // marcações já existentes são recusadas pelo booking como
    // duplicadas, não criadas de novo.
    const antes = await marcacoesDe('membro_as_2');
    await httpsCallable(gestor, 'assignMembersToSeries')({
      seriesId: SERIES_ID, memberIds: ['membro_as_2'],
    });
    const depois = await marcacoesDe('membro_as_2');

    await httpsCallable(gestor, 'assignMembersToSeries')({
      seriesId: SERIES_ID, memberIds: ['membro_as_2'],
    });
    expect(await marcacoesDe('membro_as_2')).toBe(depois);
    expect(depois).toBeGreaterThan(antes);

    const serie = await tenant.collection('sessionSeries').doc(SERIES_ID).get();
    const lista = serie.get('preAssignedMemberIds') as string[];
    expect(lista.filter((id) => id === 'membro_as_2')).toHaveLength(1);
  }, 45_000);

  it('uma série cancelada é recusada', async () => {
    await tenant.collection('sessionSeries').doc('serie_morta').set({
      serviceId: SERVICE_ID, dayOfWeek: 1, startTime: '18:00',
      durationMinutes: 60, capacity: 10, startDate: Timestamp.now(),
      status: 'cancelled',
    });

    await expect(
      httpsCallable(gestor, 'assignMembersToSeries')({
        seriesId: 'serie_morta', memberIds: ['membro_as_1'],
      }),
    ).rejects.toMatchObject({ code: 'functions/failed-precondition' });
  }, 15_000);

  it('uma série que não existe é recusada, não ignorada', async () => {
    await expect(
      httpsCallable(gestor, 'assignMembersToSeries')({
        seriesId: 'nao_existe', memberIds: ['membro_as_1'],
      }),
    ).rejects.toMatchObject({ code: 'functions/not-found' });
  }, 15_000);
});
