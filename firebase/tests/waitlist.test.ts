// Fase 11 — lista de espera.
//
// A app impõe capacidade por desenho, portanto aulas cheias são o normal
// e não a exceção. Sem fila, um cancelamento deixava um lugar vazio que
// ninguém sabia que existia: o interessado tinha de andar a abrir a app
// a ver se tinha vagado.
//
// O que interessa provar é o encadeamento completo — alguém cancela, o
// primeiro da fila fica com o lugar automaticamente — e as recusas que o
// tornam seguro.

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
const TENANT_ID = 'tenant_waitlist_test';
const SERVICE_ID = 'service_aulas';
const PLAN_ID = 'plan_standard';
const OCCURRENCE_ID = 'occ_cheia';
const FUNCTIONS_REGION = 'europe-west1';

// A ocupar o único lugar.
const OCUPANTE = 'wl_ocupante';
// Primeiro e segundo da fila.
const PRIMEIRO = 'wl_primeiro';
const SEGUNDO = 'wl_segundo';
// Sem plano: não pode sequer entrar na fila.
const SEM_PLANO = 'wl_sem_plano';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-waitlist');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
const fns: Record<string, Functions> = {};

async function clientFor(uid: string, roles: string[] = ['member']) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    `wl-${uid}`,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const f = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(f, 'localhost', 5001);
  return f;
}

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

  for (const uid of [OCUPANTE, PRIMEIRO, SEGUNDO, SEM_PLANO]) {
    await adminFirestore.doc(`tenants/${TENANT_ID}/members/${uid}`).set({
      name: uid,
      memberNumber: uid,
      status: 'active',
    });
    if (uid !== SEM_PLANO) {
      await adminFirestore
        .doc(`tenants/${TENANT_ID}/subscriptions/sub_${uid}`)
        .set({
          memberId: uid,
          planId: PLAN_ID,
          status: 'active',
          agreedPrice: 40,
          currency: 'EUR',
          activeServiceIds: [SERVICE_ID],
          startDate: new Date(),
        });
    }
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
    fns[uid] = await clientFor(uid);
  }
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

/** Uma sessão de UMA vaga, já ocupada. */
beforeEach(async () => {
  await adminFirestore.recursiveDelete(
    adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`),
  );
  const start = new Date(Date.now() + 48 * 3600_000);
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
    .set({
      serviceId: SERVICE_ID,
      startAt: Timestamp.fromDate(start),
      endAt: Timestamp.fromDate(new Date(start.getTime() + 3600_000)),
      capacity: 1,
      status: 'scheduled',
      activeBookingCount: 0,
    });

  await httpsCallable(fns[OCUPANTE], 'createBooking')({
    occurrenceId: OCCURRENCE_ID,
    memberId: OCUPANTE,
  });
});

async function waitlistIds(): Promise<string[]> {
  const snap = await adminFirestore
    .collection(
      `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}/waitlist`,
    )
    .orderBy('joinedAt')
    .get();
  return snap.docs.map((d) => d.id);
}

async function bookingStatus(memberId: string) {
  const doc = await adminFirestore
    .doc(
      `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}/bookings/${memberId}`,
    )
    .get();
  return doc.exists ? (doc.get('status') as string) : null;
}

describe('Entrar na lista de espera', () => {
  it('numa sessão cheia, entra na fila', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    expect(await waitlistIds()).toEqual([PRIMEIRO]);
  });

  it('entrar duas vezes não duplica nem avança na fila', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[SEGUNDO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: SEGUNDO,
    });
    const result = await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });

    expect((result.data as { alreadyInQueue: boolean }).alreadyInQueue).toBe(true);
    // A ordem mantém-se: tentar outra vez não é uma forma de passar à
    // frente de quem já lá estava.
    expect(await waitlistIds()).toEqual([PRIMEIRO, SEGUNDO]);
  });

  it('a posição na fila fica escrita em cada entrada', async () => {
    // O aluno não pode LISTAR a fila (quem mais espera é informação dos
    // outros), por isso a posição tem de vir escrita na entrada dele —
    // é a única forma de a app poder mostrar "és o próximo".
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[SEGUNDO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: SEGUNDO,
    });

    const base = `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`;
    const primeiro = await adminFirestore.doc(`${base}/waitlist/${PRIMEIRO}`).get();
    const segundo = await adminFirestore.doc(`${base}/waitlist/${SEGUNDO}`).get();
    expect(primeiro.get('position')).toBe(1);
    expect(segundo.get('position')).toBe(2);

    // Sair renumera quem fica: o segundo passa a próximo.
    await httpsCallable(fns[PRIMEIRO], 'leaveWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    const segundoDepois = await adminFirestore
      .doc(`${base}/waitlist/${SEGUNDO}`)
      .get();
    expect(segundoDepois.get('position')).toBe(1);
  }, 30_000);

  it('numa sessão COM vagas, recusa — devia marcar, não esperar',
    async () => {
      await adminFirestore
        .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
        .update({ capacity: 5 });

      await expect(
        httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
          occurrenceId: OCCURRENCE_ID,
          memberId: PRIMEIRO,
        }),
      ).rejects.toThrow(/vagas/i);
    });

  it('quem já tem marcação não entra na fila', async () => {
    await expect(
      httpsCallable(fns[OCUPANTE], 'joinWaitlist')({
        occurrenceId: OCCURRENCE_ID,
        memberId: OCUPANTE,
      }),
    ).rejects.toThrow();
  });

  it('sem plano que dê acesso, não entra', async () => {
    // Entrar na fila seria prometer um lugar que nunca poderia ocupar.
    await expect(
      httpsCallable(fns[SEM_PLANO], 'joinWaitlist')({
        occurrenceId: OCCURRENCE_ID,
        memberId: SEM_PLANO,
      }),
    ).rejects.toThrow(/plano/i);
  });

  it('um aluno não põe OUTRO na fila', async () => {
    await expect(
      httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
        occurrenceId: OCCURRENCE_ID,
        memberId: SEGUNDO,
      }),
    ).rejects.toThrow();
  });
});

describe('Promoção automática ao vagar um lugar', () => {
  it('quem cancela liberta o lugar para o PRIMEIRO da fila', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[SEGUNDO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: SEGUNDO,
    });

    const result = await httpsCallable(fns[OCUPANTE], 'cancelBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: OCUPANTE,
    });

    expect(
      (result.data as { promotedFromWaitlist: boolean }).promotedFromWaitlist,
    ).toBe(true);

    // O primeiro ficou com o lugar; o segundo continua à espera.
    expect(await bookingStatus(PRIMEIRO)).toBe('booked');
    expect(await bookingStatus(SEGUNDO)).toBeNull();
    expect(await waitlistIds()).toEqual([SEGUNDO]);
  }, 30_000);

  it('a sessão volta a ficar cheia — a vaga não se perde', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[OCUPANTE], 'cancelBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: OCUPANTE,
    });

    const occurrence = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .get();
    expect(occurrence.get('activeBookingCount')).toBe(1);
  }, 30_000);

  it('com a fila vazia, cancelar apenas liberta a vaga', async () => {
    const result = await httpsCallable(fns[OCUPANTE], 'cancelBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: OCUPANTE,
    });

    expect(
      (result.data as { promotedFromWaitlist: boolean }).promotedFromWaitlist,
    ).toBe(false);
    const occurrence = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .get();
    expect(occurrence.get('activeBookingCount')).toBe(0);
  }, 30_000);

  it('a marcação promovida fica registada como vinda da fila',
    async () => {
      // `source: 'waitlist'` distingue-a de um ato do próprio naquele
      // momento — quem a lê depois percebe porque é que ela existe.
      await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
        occurrenceId: OCCURRENCE_ID,
        memberId: PRIMEIRO,
      });
      await httpsCallable(fns[OCUPANTE], 'cancelBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: OCUPANTE,
      });

      const booking = await adminFirestore
        .doc(
          `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}/bookings/${PRIMEIRO}`,
        )
        .get();
      expect(booking.get('source')).toBe('waitlist');
    }, 30_000);
});

describe('Sair da lista de espera', () => {
  it('sai e deixa de ser promovido', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[SEGUNDO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: SEGUNDO,
    });
    await httpsCallable(fns[PRIMEIRO], 'leaveWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });

    expect(await waitlistIds()).toEqual([SEGUNDO]);

    await httpsCallable(fns[OCUPANTE], 'cancelBooking')({
      occurrenceId: OCCURRENCE_ID,
      memberId: OCUPANTE,
    });
    expect(await bookingStatus(SEGUNDO)).toBe('booked');
    expect(await bookingStatus(PRIMEIRO)).toBeNull();
  }, 30_000);
});

describe('Abrir mais vagas puxa a fila', () => {
  /**
   * Os triggers do Firestore correm em segundo plano: o `update`
   * devolve antes de a promoção acontecer. Esperar por uma condição é
   * mais honesto (e mais estável) do que um sleep fixo.
   */
  async function waitFor(
    check: () => Promise<boolean>,
    timeoutMs = 15_000,
  ): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (await check()) return true;
      await new Promise((resolve) => setTimeout(resolve, 400));
    }
    return false;
  }

  it('aumentar a lotação marca quem estava à espera', async () => {
    // O caso real: a aula enche, ficam pessoas na fila, e o instrutor
    // decide que cabem mais dois. Sem isto, os dois lugares novos
    // ficavam vazios com gente à espera deles.
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[SEGUNDO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: SEGUNDO,
    });

    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .update({ capacity: 3 });

    const promoted = await waitFor(async () => {
      const first = await bookingStatus(PRIMEIRO);
      const second = await bookingStatus(SEGUNDO);
      return first === 'booked' && second === 'booked';
    });

    expect(promoted).toBe(true);
    expect(await waitlistIds()).toEqual([]);
  }, 40_000);

  it('abrir UM lugar só promove UM', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });
    await httpsCallable(fns[SEGUNDO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: SEGUNDO,
    });

    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .update({ capacity: 2 });

    await waitFor(async () => (await bookingStatus(PRIMEIRO)) === 'booked');

    expect(await bookingStatus(PRIMEIRO)).toBe('booked');
    expect(await bookingStatus(SEGUNDO)).toBeNull();
    expect(await waitlistIds()).toEqual([SEGUNDO]);
  }, 40_000);

  it('reduzir a lotação não promove ninguém', async () => {
    await httpsCallable(fns[PRIMEIRO], 'joinWaitlist')({
      occurrenceId: OCCURRENCE_ID,
      memberId: PRIMEIRO,
    });

    await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .update({ capacity: 1, endAt: Timestamp.now() });

    // Nada a esperar: o que se prova é que passado tempo suficiente
    // continua sem acontecer nada.
    await new Promise((resolve) => setTimeout(resolve, 3000));
    expect(await bookingStatus(PRIMEIRO)).toBeNull();
  }, 40_000);
});
