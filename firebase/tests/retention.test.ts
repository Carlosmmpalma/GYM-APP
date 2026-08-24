// Fase 11 — painel de retenção.
//
// Num ginásio de proximidade quem desiste não cancela: deixa de
// aparecer, continua a pagar uns meses, e só depois cancela. O sinal
// existia nos dados desde a Fase 6 (presenças e faltas) mas nenhum
// ecrã o lia.
//
// O que aqui interessa provar são as decisões que fazem a diferença
// entre um número útil e um número enganador: quem entra na lista de
// risco, o que conta para as taxas, e o que fica de fora.

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
const TENANT_ID = 'tenant_retention_test';
const SERVICE_ID = 'service_aulas';
const PLAN_ID = 'plan_standard';
const FUNCTIONS_REGION = 'europe-west1';

const MANAGER = 'ret_gestor';
/** Veio ontem. */
const ASSIDUO = 'ret_assiduo';
/** Última presença há 40 dias. */
const SUMIU = 'ret_sumiu';
/** Nunca teve presença registada. */
const FANTASMA = 'ret_fantasma';
/** Sumiu, mas já não tem plano — já saiu, não está "em risco". */
const SEM_PLANO = 'ret_sem_plano';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-retention');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFns: Functions;
let memberFns: Functions;

type Overview = {
  scanDays: number;
  membersWithActivePlan: number;
  occupancy: { sessions: number; ratePercent: number | null };
  attendance: { recorded: number; noShows: number; noShowRatePercent: number | null };
  atRisk: { memberId: string; lastAttendanceAt: string | null }[];
};

async function clientFor(uid: string, roles: string[]) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    `ret-${uid}`,
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

function daysAgo(days: number) {
  return new Date(Date.now() - days * 86_400_000);
}

/**
 * Uma sessão já realizada, com presenças. `attendance` mapeia
 * memberId → apareceu ou faltou.
 */
async function pastSession(params: {
  id: string;
  days: number;
  capacity: number;
  booked: number;
  attendance?: Record<string, 'attended' | 'no_show'>;
  status?: string;
}) {
  const start = daysAgo(params.days);
  const ref = adminFirestore.doc(
    `tenants/${TENANT_ID}/sessionOccurrences/${params.id}`,
  );
  await ref.set({
    serviceId: SERVICE_ID,
    startAt: Timestamp.fromDate(start),
    endAt: Timestamp.fromDate(new Date(start.getTime() + 3600_000)),
    capacity: params.capacity,
    activeBookingCount: params.booked,
    status: params.status ?? 'scheduled',
  });
  for (const [memberId, status] of Object.entries(params.attendance ?? {})) {
    await ref.collection('attendance').doc(memberId).set({
      memberId,
      status,
      recordedBy: MANAGER,
      recordedAt: Timestamp.fromDate(start),
    });
  }
}

async function overview(riskWeeks = 3, windowDays = 30): Promise<Overview> {
  const result = await httpsCallable(
    managerFns,
    'getRetentionOverview',
  )({ riskWeeks, windowDays });
  return result.data as Overview;
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`)
    .set({ name: 'Aulas', active: true });

  for (const uid of [ASSIDUO, SUMIU, FANTASMA, SEM_PLANO]) {
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
          startDate: Timestamp.fromDate(daysAgo(200)),
        });
    } else {
      await adminFirestore
        .doc(`tenants/${TENANT_ID}/subscriptions/sub_${uid}`)
        .set({
          memberId: uid,
          planId: PLAN_ID,
          status: 'cancelled',
          agreedPrice: 40,
          currency: 'EUR',
          activeServiceIds: [SERVICE_ID],
          startDate: Timestamp.fromDate(daysAgo(200)),
        });
    }
  }

  for (const uid of [MANAGER, ASSIDUO]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }
  managerFns = await clientFor(MANAGER, ['manager']);
  memberFns = await clientFor(ASSIDUO, ['member']);
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
});

describe('Quem entra na lista de risco', () => {
  beforeEach(async () => {
    await pastSession({
      id: 'occ_ontem',
      days: 1,
      capacity: 10,
      booked: 1,
      attendance: { [ASSIDUO]: 'attended' },
    });
    await pastSession({
      id: 'occ_ha_40_dias',
      days: 40,
      capacity: 10,
      booked: 2,
      attendance: { [SUMIU]: 'attended', [SEM_PLANO]: 'attended' },
    });
  });

  it('quem veio ontem não está em risco', async () => {
    const data = await overview();
    expect(data.atRisk.map((m) => m.memberId)).not.toContain(ASSIDUO);
  }, 30_000);

  it('quem não vem há 40 dias está em risco', async () => {
    const data = await overview();
    expect(data.atRisk.map((m) => m.memberId)).toContain(SUMIU);
  }, 30_000);

  it('quem nunca teve presença registada também está em risco', async () => {
    const data = await overview();
    const fantasma = data.atRisk.find((m) => m.memberId === FANTASMA);
    expect(fantasma).toBeDefined();
    // `null` e não uma data inventada: só se procurou até `scanDays`
    // atrás, por isso o ecrã diz "sem presença nos últimos N dias" e
    // nunca "nunca veio".
    expect(fantasma?.lastAttendanceAt).toBeNull();
  }, 30_000);

  it('quem já não tem plano NÃO conta como em risco', async () => {
    // Já saiu. Contá-lo inflacionava o número e enterrava quem ainda
    // dá para recuperar.
    const data = await overview();
    expect(data.atRisk.map((m) => m.memberId)).not.toContain(SEM_PLANO);
    expect(data.membersWithActivePlan).toBe(3);
  }, 30_000);

  it('sem presença nenhuma primeiro, depois do mais antigo', async () => {
    const data = await overview();
    expect(data.atRisk[0].lastAttendanceAt).toBeNull();
  }, 30_000);

  it('alargar o período tira gente da lista', async () => {
    // Quem sumiu há 40 dias deixa de contar quando o corte é 2 meses.
    const data = await overview(8);
    expect(data.atRisk.map((m) => m.memberId)).not.toContain(SUMIU);
    expect(data.atRisk.map((m) => m.memberId)).toContain(FANTASMA);
  }, 30_000);
});

describe('Ocupação e faltas', () => {
  it('a ocupação é sobre lugares, não sobre sessões', async () => {
    // Uma aula de 10 com 2 pessoas e outra de 2 com 2 não são "50% e
    // 100%, média 75%": são 4 lugares ocupados em 12.
    await pastSession({ id: 'occ_grande', days: 3, capacity: 10, booked: 2 });
    await pastSession({ id: 'occ_pequena', days: 4, capacity: 2, booked: 2 });

    const data = await overview();
    expect(data.occupancy.sessions).toBe(2);
    expect(data.occupancy.ratePercent).toBe(33);
  }, 30_000);

  it('uma sessão FUTURA não conta para a ocupação', async () => {
    // Uma aula de amanhã com duas marcações não é uma aula com 20% de
    // ocupação: é uma aula que ainda não aconteceu.
    await pastSession({ id: 'occ_passada', days: 3, capacity: 10, booked: 5 });
    await pastSession({ id: 'occ_futura', days: -3, capacity: 10, booked: 1 });

    const data = await overview();
    expect(data.occupancy.sessions).toBe(1);
    expect(data.occupancy.ratePercent).toBe(50);
  }, 30_000);

  it('uma sessão CANCELADA não conta para a ocupação', async () => {
    await pastSession({ id: 'occ_boa', days: 3, capacity: 10, booked: 5 });
    await pastSession({
      id: 'occ_cancelada',
      days: 4,
      capacity: 10,
      booked: 0,
      status: 'cancelled',
    });

    const data = await overview();
    expect(data.occupancy.sessions).toBe(1);
    expect(data.occupancy.ratePercent).toBe(50);
  }, 30_000);

  it('a taxa de faltas é sobre presenças registadas', async () => {
    await pastSession({
      id: 'occ_com_falta',
      days: 3,
      capacity: 10,
      booked: 4,
      attendance: {
        [ASSIDUO]: 'attended',
        [SUMIU]: 'attended',
        [FANTASMA]: 'attended',
        [SEM_PLANO]: 'no_show',
      },
    });

    const data = await overview();
    expect(data.attendance.recorded).toBe(4);
    expect(data.attendance.noShows).toBe(1);
    expect(data.attendance.noShowRatePercent).toBe(25);
  }, 30_000);

  it('sem presenças registadas a taxa é null, não 0%', async () => {
    // 0% diria "não há faltas"; a verdade é que ninguém registou nada.
    await pastSession({ id: 'occ_sem_registo', days: 3, capacity: 10, booked: 4 });

    const data = await overview();
    expect(data.attendance.recorded).toBe(0);
    expect(data.attendance.noShowRatePercent).toBeNull();
  }, 30_000);

  it('fora da janela conta para a presença mas não para as taxas',
    async () => {
      // Uma presença de há 40 dias diz que a pessoa ainda aparece, mas
      // não pode entrar numa taxa anunciada como sendo de 30 dias.
      await pastSession({
        id: 'occ_antiga',
        days: 40,
        capacity: 10,
        booked: 1,
        attendance: { [SUMIU]: 'attended' },
      });

      const data = await overview(8, 30);
      expect(data.occupancy.sessions).toBe(0);
      expect(data.attendance.recorded).toBe(0);
      expect(data.atRisk.map((m) => m.memberId)).not.toContain(SUMIU);
    }, 30_000);
});

describe('Quem pode ver', () => {
  it('um aluno não consegue abrir o painel', async () => {
    await expect(
      httpsCallable(memberFns, 'getRetentionOverview')({}),
    ).rejects.toThrow();
  }, 30_000);
});
