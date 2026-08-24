// Fase 11 (bug encontrado a avaliar o que faltava) — um plano com data
// de fim já passada continuava a dar acesso.
//
// `endDate` era guardado, mostrado na ficha do aluno... e ignorado por
// toda a lógica de autorização, que olhava só para `status == 'active'`.
// Na prática: um plano terminado em março deixava marcar aulas em
// agosto, e a ficha dizia "Ativo" com a data de fim já passada.
//
// Política implementada: vale até ao FIM do dia do `endDate` — quem tem
// plano "até 31 de março" treina no dia 31. Sem tolerância depois disso.

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
const TENANT_ID = 'tenant_expiry_test';
const SERVICE_ID = 'service_aulas';
const PLAN_ID = 'plan_standard';
const FUNCTIONS_REGION = 'europe-west1';

const EXPIRADO = 'member_expirado';
const VALIDO = 'member_valido';
const HOJE = 'member_acaba_hoje';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-expiry');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
const functionsByMember: Record<string, Functions> = {};

const OCCURRENCE_ID = 'occ_expiry';

function daysFromNow(days: number) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d;
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

  // Três alunos, todos com `status: 'active'`. O que muda é a data de
  // fim — que era exatamente o que ninguém verificava.
  const casos: [string, Date | null][] = [
    [EXPIRADO, daysFromNow(-30)],
    [VALIDO, daysFromNow(30)],
    // Acaba HOJE: tem de continuar a poder treinar. Cortar às 00:00 do
    // próprio dia tiraria um dia a quem pagou por ele.
    [HOJE, new Date()],
  ];

  for (const [uid, endDate] of casos) {
    await adminFirestore.doc(`tenants/${TENANT_ID}/members/${uid}`).set({
      name: uid,
      memberNumber: uid,
      status: 'active',
    });
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/subscriptions/sub_${uid}`)
      .set({
        memberId: uid,
        planId: PLAN_ID,
        status: 'active',
        agreedPrice: 40,
        currency: 'EUR',
        activeServiceIds: [SERVICE_ID],
        startDate: Timestamp.fromDate(daysFromNow(-90)),
        endDate: endDate ? Timestamp.fromDate(endDate) : null,
      });

    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);

    const app = initializeClientApp(
      { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
      `expiry-${uid}`,
    );
    clientApps.push(app);
    const auth = getAuth(app);
    connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
    await signInWithCustomToken(
      auth,
      await adminAuth.createCustomToken(uid, {
        tenantId: TENANT_ID,
        roles: ['member'],
      }),
    );
    const fns = getFunctions(app, FUNCTIONS_REGION);
    connectFunctionsEmulator(fns, 'localhost', 5001);
    functionsByMember[uid] = fns;
  }
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

beforeEach(async () => {
  const start = daysFromNow(2);
  await adminFirestore.recursiveDelete(
    adminFirestore.doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`),
  );
  await adminFirestore
    .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
    .set({
      serviceId: SERVICE_ID,
      startAt: Timestamp.fromDate(start),
      endAt: Timestamp.fromDate(new Date(start.getTime() + 3600_000)),
      capacity: 10,
      status: 'scheduled',
      activeBookingCount: 0,
    });
});

describe('Planos com data de fim', () => {
  it('um plano dentro do prazo deixa marcar', async () => {
    await expect(
      httpsCallable(functionsByMember[VALIDO], 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: VALIDO,
      }),
    ).resolves.toBeTruthy();

    // A marcação guarda QUANDO a sessão acontece. Sem este campo, "as
    // minhas marcações" não conseguia ordenar por data, esconder as
    // que já passaram, nem saber qual é a próxima sem ler uma
    // ocorrência por marcação.
    const booking = await adminFirestore
      .doc(
        `tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}/bookings/${VALIDO}`,
      )
      .get();
    expect(booking.get('startAt')).toBeDefined();
    expect(
      (booking.get('startAt') as Timestamp).toDate().getTime(),
    ).toBeGreaterThan(Date.now());
  });

  it('um plano EXPIRADO já não deixa marcar', async () => {
    // O bug: `status` continua 'active' na base de dados, e era só isso
    // que a autorização olhava.
    await expect(
      httpsCallable(functionsByMember[EXPIRADO], 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: EXPIRADO,
      }),
    ).rejects.toThrow();
  });

  it('um plano que acaba HOJE ainda deixa marcar', async () => {
    // Vale até ao fim do dia. Cortar às 00:00 tiraria um dia a quem
    // pagou por ele — e é o tipo de detalhe que gera uma reclamação ao
    // balcão.
    await expect(
      httpsCallable(functionsByMember[HOJE], 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: HOJE,
      }),
    ).resolves.toBeTruthy();
  });

  it('a recusa é por elegibilidade, não por capacidade', async () => {
    // A sessão tem 10 vagas e está vazia: se o expirado fosse recusado
    // por outra razão, este teste passaria pelo motivo errado.
    const occurrence = await adminFirestore
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/${OCCURRENCE_ID}`)
      .get();
    expect(occurrence.get('activeBookingCount')).toBe(0);

    await expect(
      httpsCallable(functionsByMember[EXPIRADO], 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: EXPIRADO,
      }),
    ).rejects.toThrow(/plano ativo|elegív|eligib/i);
  });
});

// Auditoria da Fase 11 — desativar um membro não fazia nada.
//
// O Gestor desligava "Membro ativo" na ficha do aluno e ele continuava
// a marcar aulas: a autorização olhava só para as subscrições, e a
// subscrição de quem sai raramente é cancelada no mesmo instante. Na
// prática o interruptor era uma etiqueta.
describe('Conta desativada', () => {
  it('um membro desativado não consegue marcar', async () => {
    await adminFirestore
      .doc(`tenants/${TENANT_ID}/members/${VALIDO}`)
      .update({ status: 'inactive' });

    try {
      await expect(
        httpsCallable(functionsByMember[VALIDO], 'createBooking')({
          occurrenceId: OCCURRENCE_ID,
          memberId: VALIDO,
        }),
      ).rejects.toThrow();
    } finally {
      await adminFirestore
        .doc(`tenants/${TENANT_ID}/members/${VALIDO}`)
        .update({ status: 'active' });
    }
  });

  it('reativar devolve o acesso', async () => {
    // O plano não foi tocado — o que mudou foi só o estado da conta.
    await expect(
      httpsCallable(functionsByMember[VALIDO], 'createBooking')({
        occurrenceId: OCCURRENCE_ID,
        memberId: VALIDO,
      }),
    ).resolves.toBeTruthy();
  });
});
