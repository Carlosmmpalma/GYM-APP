// Cancelar uma série — e o que a escrita direta nunca fazia.
//
// `SessionSeriesRepository.cancelSeries` era um batch do cliente que
// punha `status: 'cancelled'` na série e em cada ocorrência futura. As
// Rules passaram a exigir, no `update` de `sessionOccurrences`, que
// `status` não mude por escrita direta — e como um batch é atómico, o
// cancelamento inteiro falhava com `permission-denied`. A um Gestor.
//
// A regra está testada desde a altura em que entrou
// (`operations-rules.test.ts`). O que ninguém ligou foi que o
// `cancelSeries` fazia exatamente aquilo que ela proíbe.
//
// E mesmo que passasse: só mudava `status`. As marcações ficavam
// `booked` numa aula cancelada e a utilização semanal continuava
// consumida — o aluno perdia a sessão do plano por causa de uma aula
// que o estúdio cancelou. É essa parte que este teste fixa.

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
const TENANT_ID = 'tenant_cancel_series';
const MEMBER_ID = 'member_cs';
const SERVICE_ID = 'service_cs';
const SERIES_ID = 'series_cs';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-cancel-series');
const adminFirestore = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFunctions: Functions;

/** A semana ISO em que a utilização foi contada. */
function isoWeekKey(date: Date): string {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNumber = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  d.setUTCDate(d.getUTCDate() + 4 - dayNumber);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

const daquiA2Dias = new Date(Date.now() + 2 * 86_400_000);
const periodo = isoWeekKey(daquiA2Dias);

beforeAll(async () => {
  await adminFirestore.doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`).set({
    name: 'Membro do cancelamento',
    memberNumber: '000901',
    status: 'active',
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/services/${SERVICE_ID}`).set({
    name: 'Aulas de grupo',
    active: true,
  });
  await adminFirestore.doc(`tenants/${TENANT_ID}/sessionSeries/${SERIES_ID}`).set({
    serviceId: SERVICE_ID,
    dayOfWeek: 1,
    startTime: '18:00',
    durationMinutes: 60,
    capacity: 10,
    startDate: Timestamp.now(),
    status: 'active',
  });

  // Uma ocorrência futura desta série, com o membro inscrito.
  await adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_cs`).set({
    serviceId: SERVICE_ID,
    seriesId: SERIES_ID,
    startAt: Timestamp.fromDate(daquiA2Dias),
    endAt: Timestamp.fromDate(new Date(daquiA2Dias.getTime() + 3_600_000)),
    capacity: 10,
    status: 'scheduled',
    activeBookingCount: 1,
  });
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_cs/bookings/${MEMBER_ID}`)
    .set({
      memberId: MEMBER_ID,
      status: 'booked',
      source: 'self',
      isExtra: false,
      serviceId: SERVICE_ID,
      period: periodo,
      startAt: Timestamp.fromDate(daquiA2Dias),
    });

  // A utilização que essa marcação consumiu.
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/usage/${MEMBER_ID}_${SERVICE_ID}_${periodo}`)
    .set({ memberId: MEMBER_ID, serviceId: SERVICE_ID, period: periodo, used: 1 });

  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-key' },
    'client-manager-cancel-series',
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  const token = await adminAuth.createCustomToken('manager_cs', {
    tenantId: TENANT_ID,
    roles: ['manager'],
  });
  await signInWithCustomToken(auth, token);
  managerFunctions = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(managerFunctions, 'localhost', 5001);
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

describe('cancelSeriesForStudio', () => {
  it('cancela a série, as aulas futuras E devolve a utilização', async () => {
    const result = await httpsCallable(managerFunctions, 'cancelSeriesForStudio')({
      seriesId: SERIES_ID,
    });
    expect(result.data).toMatchObject({
      cancelledOccurrences: 1,
      cancelledBookings: 1,
    });

    const serie = await adminFirestore.doc(`tenants/${TENANT_ID}/sessionSeries/${SERIES_ID}`).get();
    expect(serie.get('status')).toBe('cancelled');

    const occ = await adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_cs`).get();
    expect(occ.get('status')).toBe('cancelled');
    expect(occ.get('activeBookingCount')).toBe(0);

    // A marcação deixa de estar ativa...
    const booking = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_cs/bookings/${MEMBER_ID}`)
      .get();
    expect(booking.get('status')).not.toBe('booked');

    // ...e a sessão volta ao limite semanal. É esta a parte que a
    // escrita direta nunca fazia: o aluno perdia a sessão do plano por
    // causa de uma aula que o estúdio cancelou.
    const usage = await adminFirestore
      .doc(`tenants/${TENANT_ID}/usage/${MEMBER_ID}_${SERVICE_ID}_${periodo}`)
      .get();
    expect(usage.get('used')).toBe(0);
  }, 20_000);

  it('uma série que não existe é recusada, não ignorada em silêncio', async () => {
    await expect(
      httpsCallable(managerFunctions, 'cancelSeriesForStudio')({ seriesId: 'nao_existe' }),
    ).rejects.toMatchObject({ code: 'functions/not-found' });
  }, 15_000);
});
