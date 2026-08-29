// 🔴 Fase 5 — Security Rules para sessionSeries e para a escrita de
// sessionOccurrences pelo Manager (create/update, sem poder tocar em
// activeBookingCount).
//
// Cobre as invariantes novas nesta fase:
//   1. `sessionSeries` — leitura ampla no tenant, escrita só Manager
//      (mesmo padrão de `plans`/`services`, Fase 3).
//   2. `sessionOccurrences` deixou de ser `allow write: if false`
//      sempre (Fase 4) — Manager volta a poder criar/editar uma
//      ocorrência, MAS `activeBookingCount` continua exclusivo das
//      Cloud Functions de booking: `create` exige que nasça a 0,
//      `update` exige que o valor não mude nesta escrita.
//   3. Regressão da Fase 4: `bookings` (subcoleção) continua SEMPRE
//      fechada a escrita de cliente, mesmo para um Manager.
// Isolamento entre tenants é a mesma regra (`belongsToTenant`) já
// coberta exaustivamente em `tenant-isolation.test.ts`.
//
// Precisa do emulador do Firestore a correr. Corre com, a partir da
// raiz do projeto (onde está o firebase.json):
//   firebase emulators:exec --only firestore "npm --prefix firebase/tests test"

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const TENANT_A = 'tenant_a_real';
const TENANT_B = 'tenant_b_ghost';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  // projectId próprio — mesmo motivo documentado desde a Fase 2
  // (`tenant-isolation.test.ts`): ficheiros de teste correm em paralelo
  // e cada um faz clearFirestore(); partilhar projectId entre ficheiros
  // causa contaminação cruzada.
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-gym-saas-dev-session-series-test',
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`tenants/${TENANT_A}`).set({ name: 'Tenant A (real)' });
    await db.doc(`tenants/${TENANT_A}/services/service_1`).set({
      name: 'Aula de Grupo',
      active: true,
    });
    await db.doc(`tenants/${TENANT_A}/sessionSeries/series_1`).set({
      serviceId: 'service_1',
      instructorId: null,
      dayOfWeek: 1,
      startTime: '18:00',
      durationMinutes: 60,
      capacity: 6,
      startDate: new Date(),
      preAssignedMemberIds: [],
      status: 'active',
    });
    await db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).set({
      serviceId: 'service_1',
      seriesId: 'series_1',
      startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
      capacity: 6,
      status: 'scheduled',
      activeBookingCount: 2,
    });
    // Uma aula sem ninguém inscrito — o caso "criei por engano".
    await db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_vazia`).set({
      serviceId: 'service_1',
      seriesId: null,
      startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
      capacity: 6,
      status: 'scheduled',
      activeBookingCount: 0,
    });
    await db.doc(`tenants/${TENANT_A}/members/member_a1`).set({
      memberNumber: '000001',
      name: 'Rita Ferreira',
      status: 'active',
      phone: '',
      email: '',
    });
    await db.doc(`tenants/${TENANT_A}/members/member_a2`).set({
      memberNumber: '000002',
      name: 'Outro Membro',
      status: 'active',
      phone: '',
      email: '',
    });

    await db.doc(`tenants/${TENANT_B}`).set({ name: 'Tenant B (fantasma)' });
  });
});

function contextFor(uid: string, tenantId: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

describe('Security Rules — sessionSeries (Fase 5)', () => {
  it('um membro consegue LER as séries do próprio tenant', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/sessionSeries/series_1`).get());
  });

  it('um membro NÃO consegue CRIAR uma série', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionSeries/series_2`).set({
        serviceId: 'service_1',
        dayOfWeek: 2,
        startTime: '10:00',
        durationMinutes: 60,
        capacity: 1,
        startDate: new Date(),
        preAssignedMemberIds: [],
        status: 'active',
      }),
    );
  });

  it('um Manager do tenant CONSEGUE criar uma série', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionSeries/series_2`).set({
        serviceId: 'service_1',
        dayOfWeek: 2,
        startTime: '10:00',
        durationMinutes: 60,
        capacity: 1,
        startDate: new Date(),
        preAssignedMemberIds: [],
        status: 'active',
      }),
    );
  });

  it('um Manager CONSEGUE cancelar uma série existente', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionSeries/series_1`).update({ status: 'cancelled' }),
    );
  });

  it('um Manager de OUTRO tenant NÃO consegue criar série no tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionSeries/series_intruder`).set({
        serviceId: 'service_1',
        dayOfWeek: 2,
        startTime: '10:00',
        durationMinutes: 60,
        capacity: 1,
        startDate: new Date(),
        preAssignedMemberIds: [],
        status: 'active',
      }),
    );
  });
});

describe('Security Rules — sessionOccurrences escritas por Manager (Fase 5)', () => {
  it('um membro NÃO consegue criar uma ocorrência ad-hoc', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_adhoc`).set({
        serviceId: 'service_1',
        startAt: new Date(),
        endAt: new Date(),
        capacity: 1,
        status: 'scheduled',
        activeBookingCount: 0,
      }),
    );
  });

  it('um Manager CONSEGUE criar uma ocorrência ad-hoc a nascer com activeBookingCount 0', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_adhoc`).set({
        serviceId: 'service_1',
        startAt: new Date(),
        endAt: new Date(),
        capacity: 1,
        status: 'scheduled',
        activeBookingCount: 0,
      }),
    );
  });

  it('um Manager NÃO consegue criar uma ocorrência já com activeBookingCount > 0', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_cheat`).set({
        serviceId: 'service_1',
        startAt: new Date(),
        endAt: new Date(),
        capacity: 1,
        status: 'scheduled',
        activeBookingCount: 1,
      }),
    );
  });

  it('um Manager CONSEGUE editar capacidade/hora de uma ocorrência sem tocar em activeBookingCount', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({
        capacity: 8,
        startAt: new Date(Date.now() + 48 * 60 * 60 * 1000),
      }),
    );
  });

  it('um Manager NÃO consegue alterar activeBookingCount diretamente', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({
        activeBookingCount: 999,
      }),
    );
  });

  // Fase 6: esta escrita passou a ser bloqueada mesmo para o Manager —
  // cancelar tem de cascatar para os bookings ativos (libertar vaga +
  // devolver usage), o que só a Cloud Function `cancelOccurrenceForStudio`
  // (Admin SDK) faz. Ver `operations-rules.test.ts` (Fase 6) para a
  // cobertura completa desta invariante.
  it('um Manager já NÃO consegue mudar status diretamente (Fase 6 — passou por Cloud Function)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({ status: 'cancelled' }),
    );
  });

  it('ninguém consegue apagar uma ocorrência', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).delete());
  });

  it('um Manager de OUTRO tenant NÃO consegue editar ocorrência do tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({ capacity: 1 }),
    );
  });
});

describe('Security Rules — bookings continuam fechados a escrita de cliente (regressão Fase 4)', () => {
  it('nem um Manager consegue criar diretamente um booking', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/bookings/member_a1`).set({
        memberId: 'member_a1',
        status: 'booked',
        source: 'manager',
        isExtra: false,
      }),
    );
  });
});

describe('Security Rules — members: auto-atualização de contacto (Fase 5, UC02)', () => {
  it('o próprio membro consegue atualizar phone/email do seu documento', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({
        phone: '912345678',
        email: 'rita@example.com',
      }),
    );
  });

  it('o próprio membro NÃO consegue alterar memberNumber/status do seu documento', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({
        phone: '912345678',
        memberNumber: '999999',
      }),
    );
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({ status: 'inactive' }),
    );
  });

  it('um membro NÃO consegue atualizar o documento de OUTRO membro', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a2`).update({
        phone: '912345678',
      }),
    );
  });

  it('um Manager continua a poder escrever livremente (ex.: desativar um membro)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({ status: 'inactive' }),
    );
  });

  it('um Manager de OUTRO tenant NÃO consegue escrever no membro do tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({ status: 'inactive' }),
    );
  });
});

describe('Security Rules — eliminar aulas continua fechado ao cliente', () => {
  // Chegou a abrir-se `delete` para aulas vazias, e foi um erro:
  // `activeBookingCount == 0` não quer dizer "sem marcações" (cancelar
  // deixa o documento com `status: 'cancelled'`), e o cliente não pode
  // limpar as subcoleções — `bookings` e `waitlist` são `write: false`.
  // A operação passou para `deleteCatalogueEntry`, que apaga tudo e
  // recusa aulas de série. Ver `delete-catalogue-entry.test.ts`.

  it('nem o Manager elimina uma aula por escrita direta', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_vazia`).delete(),
    );
  });

  it('nem sequer uma sem inscritos', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).delete(),
    );
  });
});
