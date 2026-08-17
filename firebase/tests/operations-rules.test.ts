// 🔴 Fase 6 — Security Rules das operações do dia a dia:
//   1. `modalities` — leitura ampla no tenant, escrita só Manager
//      (mesmo padrão de `services`/`plans`).
//   2. `attendance` (subcoleção de sessionOccurrences) — leitura ampla,
//      escrita Manager OU Instrutor, nunca um membro.
//   3. `sessionOccurrences.status` — bloqueado a escrita direta mesmo
//      para Manager (cancelar cascata para bookings ativos, só a Cloud
//      Function `cancelOccurrenceForStudio` faz isso).
//   4. `members.fcmTokens` (UC21) — o próprio membro pode escrever,
//      mesma regra restrita de `phone`/`email` desde a Fase 5.
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
    projectId: 'demo-gym-saas-dev-operations-test',
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
    await db.doc(`tenants/${TENANT_A}/modalities/modality_1`).set({
      name: 'Pilates',
      active: true,
      serviceIds: ['service_1'],
    });
    await db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).set({
      serviceId: 'service_1',
      seriesId: null,
      instructorId: 'instructor_a',
      modalityId: 'modality_1',
      startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
      capacity: 6,
      status: 'scheduled',
      activeBookingCount: 1,
    });
    await db.doc(`tenants/${TENANT_A}/members/member_a1`).set({
      memberNumber: '000001',
      name: 'Rita Ferreira',
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

describe('Security Rules — modalities (Fase 6)', () => {
  it('um membro consegue LER as modalidades do próprio tenant', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/modalities/modality_1`).get());
  });

  it('um membro NÃO consegue criar uma modalidade', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/modalities/modality_2`).set({
        name: 'Hyrox',
        active: true,
        serviceIds: [],
      }),
    );
  });

  it('um Instrutor também NÃO consegue criar uma modalidade (Manager-only)', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/modalities/modality_2`).set({
        name: 'Hyrox',
        active: true,
        serviceIds: [],
      }),
    );
  });

  it('um Manager CONSEGUE criar/editar uma modalidade', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/modalities/modality_2`).set({
        name: 'Hyrox',
        active: true,
        serviceIds: [],
      }),
    );
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/modalities/modality_1`).update({ active: false }),
    );
  });

  it('um Manager de OUTRO tenant NÃO consegue criar modalidade no tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/modalities/modality_intruder`).set({
        name: 'Hyrox',
        active: true,
        serviceIds: [],
      }),
    );
  });
});

describe('Security Rules — attendance (Fase 6, UC10-A)', () => {
  it('um membro consegue LER a presença da própria sessão', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/attendance/member_a1`).get(),
    );
  });

  it('um membro NÃO consegue registar a própria presença', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/attendance/member_a1`).set({
        memberId: 'member_a1',
        status: 'attended',
        recordedBy: 'member_a1',
        recordedAt: new Date(),
      }),
    );
  });

  it('um Instrutor CONSEGUE registar presença', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/attendance/member_a1`).set({
        memberId: 'member_a1',
        status: 'attended',
        recordedBy: 'instructor_a',
        recordedAt: new Date(),
      }),
    );
  });

  it('um Manager CONSEGUE registar presença', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/attendance/member_a1`).set({
        memberId: 'member_a1',
        status: 'no_show',
        recordedBy: 'manager_a',
        recordedAt: new Date(),
      }),
    );
  });

  it('um Instrutor de OUTRO tenant NÃO consegue registar presença no tenant A', async () => {
    const db = contextFor('instructor_b', TENANT_B, ['instructor']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/attendance/member_a1`).set({
        memberId: 'member_a1',
        status: 'attended',
        recordedBy: 'instructor_b',
        recordedAt: new Date(),
      }),
    );
  });
});

describe('Security Rules — sessionOccurrences.status bloqueado a escrita direta (Fase 6)', () => {
  it('um Manager NÃO consegue cancelar (status) diretamente — só via Cloud Function', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({ status: 'cancelled' }),
    );
  });

  it('um Manager continua a poder editar outros campos (capacidade/instrutor/modalidade)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({
        capacity: 8,
        instructorId: 'instructor_b',
        modalityId: null,
      }),
    );
  });
});

describe('Security Rules — members.fcmTokens (Fase 6, UC21)', () => {
  it('o próprio membro consegue registar o token de FCM do seu dispositivo', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({
        fcmTokens: ['token_abc'],
      }),
    );
  });

  it('o próprio membro continua a NÃO conseguir alterar memberNumber junto com fcmTokens', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).update({
        fcmTokens: ['token_abc'],
        memberNumber: '999999',
      }),
    );
  });

  it('um membro NÃO consegue registar um token no documento de OUTRO membro', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/members/member_a2`)
        .set({ memberNumber: '000002', name: 'Outro Membro', status: 'active' });
    });

    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a2`).update({
        fcmTokens: ['token_intruder'],
      }),
    );
  });
});

// Fase 8 (revisão geral) — duas lacunas de autorização que sobreviveram
// desde a Fase 1 com o argumento "só o Gestor mexe nisto na UI":
//   * `staff/{id}` tinha `allow read, write: if belongsToTenant`, ou
//     seja qualquer ALUNO podia desativar/editar um instrutor;
//   * `tenants/{id}` idem — qualquer aluno podia renomear o ginásio ou
//     pô-lo a `suspended`.
// Nenhuma das duas era escalada de privilégios (os roles vêm dos custom
// claims, nunca destes documentos), mas ambas eram escrita indevida a
// sério, não só um ecrã escondido.
describe('Security Rules — staff e documento do tenant (Fase 8, revisão geral)', () => {
  it('um membro NÃO consegue desativar um instrutor', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/staff/instructor_1`)
        .set({ name: 'Rita', roles: ['instructor'], status: 'active' });
    });

    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/staff/instructor_1`).update({ status: 'inactive' }),
    );
  });

  it('um membro CONTINUA a poder LER o staff (nome do instrutor da sessão)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/staff/instructor_1`)
        .set({ name: 'Rita', roles: ['instructor'], status: 'active' });
    });

    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/staff/instructor_1`).get());
  });

  it('um Manager CONSEGUE editar o staff', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/staff/instructor_1`)
        .set({ name: 'Rita', roles: ['instructor'], status: 'active' });
    });

    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/staff/instructor_1`).update({ status: 'inactive' }),
    );
  });

  it('o próprio staff CONSEGUE registar o seu token FCM (UC21)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/staff/instructor_1`)
        .set({ name: 'Rita', roles: ['instructor'], status: 'active' });
    });

    const db = contextFor('instructor_1', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/staff/instructor_1`).update({ fcmTokens: ['token_1'] }),
    );
  });

  it('o próprio staff NÃO consegue dar-se a si mesmo o role de manager', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/staff/instructor_1`)
        .set({ name: 'Rita', roles: ['instructor'], status: 'active' });
    });

    const db = contextFor('instructor_1', TENANT_A, ['instructor']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/staff/instructor_1`).update({ roles: ['manager'] }),
    );
  });

  it('um membro NÃO consegue escrever no documento do tenant', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}`).update({ name: 'Ginásio Renomeado' }),
    );
  });

  it('um Manager CONSEGUE escrever no documento do tenant', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}`).update({ name: 'NXT Performance Studio' }),
    );
  });
});
