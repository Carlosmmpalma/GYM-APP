// 🔴 Fase 7 — Security Rules do Treino livre (UC09/UC17-A, UC10-A
// fechados). Cobre o "Done quando" crítico desta fase: "um aluno
// nunca consegue, por rules nem por UI, ver o nome de outro aluno
// inscrito no treino livre — mas o Gestor consegue."
//   1. `freeTrainingSchedules` — só Manager lê rascunho/sugestão;
//      qualquer membro do tenant lê uma semana `published`. Escrita
//      sempre `false` (Cloud Functions).
//   2. `slots` — mesma visibilidade da semana-mãe (via `get()` ao
//      documento pai). Manager escreve diretamente (montar a
//      grelha); `activeBookingCount` continua exclusivo das Cloud
//      Functions. `delete` é permitido ao Manager sempre que o bloco
//      não tiver ninguém marcado — publicado ou não. A condição
//      "só antes de publicar" saiu: deixava blocos vazios presos na
//      grelha depois de publicada, sem proteger nada que
//      `activeBookingCount == 0` já não proteja.
//   3. `bookings` — um Aluno só consegue `get` a PRÓPRIA marcação,
//      nunca `list` nem `get` a de outro membro (é assim que "só vê
//      contagem, nunca nomes" é garantido do lado do servidor).
//      Instrutor/Gestor conseguem listar todas.
//   4. `attendance` — Manager-only (UC10-A fechado: "o Gestor, não o
//      Instrutor, que só tem leitura sobre o treino livre").
// Isolamento entre tenants é a mesma regra já coberta exaustivamente
// em `tenant-isolation.test.ts`.
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
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const TENANT_A = 'tenant_a_real';
const TENANT_B = 'tenant_b_ghost';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-gym-saas-dev-free-training-test',
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
      name: 'Treino sem acompanhamento',
      active: true,
    });

    await db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft`).set({
      weekStart: new Date('2026-08-17'),
      status: 'draft',
      serviceId: 'service_1',
    });
    await db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_suggested`).set({
      weekStart: new Date('2026-08-24'),
      status: 'suggested',
      serviceId: 'service_1',
    });
    await db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_published`).set({
      weekStart: new Date('2026-08-31'),
      status: 'published',
      serviceId: 'service_1',
    });

    await db
      .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_draft`)
      .set({
        serviceId: 'service_1',
        startAt: new Date('2026-08-17T06:00:00Z'),
        endAt: new Date('2026-08-17T08:00:00Z'),
        capacity: 10,
        activeBookingCount: 0,
      });
    await db
      .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published`)
      .set({
        serviceId: 'service_1',
        startAt: new Date('2026-08-31T06:00:00Z'),
        endAt: new Date('2026-08-31T08:00:00Z'),
        capacity: 10,
        activeBookingCount: 2,
      });

    // Um bloco publicado e VAZIO: existe para o caso que a regra
    // antiga não sabia distinguir de um bloco cheio.
    await db
      .doc(
        `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published_empty`,
      )
      .set({
        serviceId: 'service_free',
        startAt: new Date('2026-01-08T08:00:00Z'),
        endAt: new Date('2026-01-08T09:00:00Z'),
        capacity: 4,
        activeBookingCount: 0,
      });
    await db
      .doc(
        `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings/member_a1`,
      )
      .set({
        memberId: 'member_a1',
        status: 'booked',
        source: 'self',
        isExtra: false,
        serviceId: 'service_1',
      });
    await db
      .doc(
        `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings/member_a2`,
      )
      .set({
        memberId: 'member_a2',
        status: 'booked',
        source: 'self',
        isExtra: false,
        serviceId: 'service_1',
      });

    // Fase 8 (auditoria funcional, UC17-A fechado) — para testar que
    // `delete` continua bloqueado mesmo pré-publish quando o slot já
    // tem alguém marcado (defesa extra da rule, ainda que na prática
    // marcar exija a semana já publicada).
    await db
      .doc(
        `tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_draft_with_bookings`,
      )
      .set({
        serviceId: 'service_1',
        startAt: new Date('2026-08-17T10:00:00Z'),
        endAt: new Date('2026-08-17T12:00:00Z'),
        capacity: 10,
        activeBookingCount: 1,
      });

    await db.doc(`tenants/${TENANT_B}`).set({ name: 'Tenant B (fantasma)' });
  });
});

function contextFor(uid: string, tenantId: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

describe('Security Rules — freeTrainingSchedules (Fase 7, UC17-A)', () => {
  it('um membro NÃO consegue ler uma semana em rascunho', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft`).get(),
    );
  });

  it('um membro NÃO consegue ler uma semana sugerida (por aprovar)', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_suggested`).get(),
    );
  });

  // Fase 10 — bug reportado a testar a app como Aluno: o ecrã "Treino
  // livre" mostrava `[cloud_firestore/permission-denied] Null value
  // error for 'get'` em vez do estado vazio, sempre que a semana ainda
  // não tinha grelha nenhuma. A causa era `resource.data.status` num
  // documento inexistente — em Rules isso é um ERRO de avaliação, não um
  // `false`, e o cliente recebe permission-denied. Um Aluno tem de poder
  // ler um weekId que não existe (e receber "não existe"), senão não há
  // forma de distinguir "sem grelha publicada" de "sem acesso".
  it('um membro CONSEGUE ler uma semana que não existe (e recebe "não existe")',
    async () => {
      const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
      const snapshot = await assertSucceeds(
        db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_inexistente`).get(),
      );
      expect(snapshot.exists).toBe(false);
    });

  // Os SLOTS de uma semana não publicada continuam fechados — inclusive
  // os de uma semana que não existe. É a regra do UC17-A ("nenhum aluno
  // pode ver uma grelha em estado 'sugerido'") e a app respeita-a: só
  // lista slots depois de confirmar, no documento da semana, que está
  // publicada.
  it('um membro NÃO consegue listar os slots de uma semana que não existe',
    async () => {
      const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
      await assertFails(
        db
          .collection(
            `tenants/${TENANT_A}/freeTrainingSchedules/week_inexistente/slots`,
          )
          .get(),
      );
    });

  it('um membro CONSEGUE ler uma semana publicada', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_published`).get(),
    );
  });

  it('um Manager CONSEGUE ler rascunho, sugestão e publicada', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft`).get(),
    );
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_suggested`).get(),
    );
  });

  it('nem um Manager consegue escrever diretamente (só via Cloud Function)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_new`).set({
        weekStart: new Date(),
        status: 'draft',
        serviceId: 'service_1',
      }),
    );
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft`)
        .update({ status: 'published' }),
    );
  });

  it('um Manager de OUTRO tenant NÃO consegue ler a semana do tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_published`).get(),
    );
  });
});

describe('Security Rules — slots (Fase 7)', () => {
  it('um membro NÃO consegue ler um slot de uma semana em rascunho', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_draft`)
        .get(),
    );
  });

  it('um membro CONSEGUE ler um slot de uma semana publicada', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published`,
        )
        .get(),
    );
  });

  it('um Manager CONSEGUE criar um slot a nascer com activeBookingCount 0', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_new`)
        .set({
          serviceId: 'service_1',
          startAt: new Date(),
          endAt: new Date(),
          capacity: 10,
          activeBookingCount: 0,
        }),
    );
  });

  it('um membro NÃO consegue criar um slot', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_new`)
        .set({
          serviceId: 'service_1',
          startAt: new Date(),
          endAt: new Date(),
          capacity: 10,
          activeBookingCount: 0,
        }),
    );
  });

  it('um Manager NÃO consegue alterar activeBookingCount diretamente', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published`,
        )
        .update({ activeBookingCount: 999 }),
    );
  });

  it('um Manager CONSEGUE editar a capacidade sem tocar em activeBookingCount', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published`,
        )
        .update({ capacity: 12 }),
    );
  });

  it('um Manager NÃO consegue apagar um slot com alguém marcado', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published`,
        )
        .delete(),
    );
  });

  it('um Manager CONSEGUE apagar um slot publicado mas VAZIO', async () => {
    // A regra exigia também que a semana não estivesse publicada. Isso
    // apanhava o caso errado: depois de publicar, um bloco sem ninguém
    // inscrito só podia ir a capacidade 0 e ficava na grelha a dizer
    // "0/0" — visível aos alunos, sem servir para nada. O que protege
    // continua a proteger (ver o teste acima); o que era ruído saiu.
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published_empty`,
        )
        .delete(),
    );
  });

  it('um Manager CONSEGUE apagar um slot de uma semana ainda em rascunho', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_draft`)
        .delete(),
    );
  });

  it('um membro NÃO consegue apagar um slot, mesmo de uma semana em rascunho', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_draft`)
        .delete(),
    );
  });

  it('um Manager NÃO consegue apagar um slot pré-publish com alguém já marcado', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_draft/slots/slot_draft_with_bookings`,
        )
        .delete(),
    );
  });
});

describe('Security Rules — bookings de treino livre (Fase 7, "Done" crítico)', () => {
  it('um membro CONSEGUE ler a PRÓPRIA marcação', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings/member_a1`,
        )
        .get(),
    );
  });

  it('um membro NÃO consegue ler a marcação de OUTRO membro (nunca vê nomes)', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings/member_a2`,
        )
        .get(),
    );
  });

  it('um membro NÃO consegue listar todas as marcações do slot (só contagem, nunca nomes)', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .collection(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings`,
        )
        .get(),
    );
  });

  it('um Instrutor CONSEGUE listar todas as marcações do slot (nomes)', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db
        .collection(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings`,
        )
        .get(),
    );
  });

  it('um Manager CONSEGUE listar todas as marcações do slot (nomes)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .collection(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings`,
        )
        .get(),
    );
  });

  it('nem um Manager consegue criar diretamente uma marcação (só via Cloud Function)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/bookings/member_a3`,
        )
        .set({ memberId: 'member_a3', status: 'booked', source: 'manager', isExtra: false }),
    );
  });
});

describe('Security Rules — attendance de treino livre (Fase 7, UC10-A fechado)', () => {
  it('um Manager CONSEGUE registar presença', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .set({
          memberId: 'member_a1',
          status: 'attended',
          recordedBy: 'manager_a',
          recordedAt: new Date(),
        }),
    );
  });

  it('um Instrutor NÃO consegue registar presença — só leitura sobre o treino livre', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .set({
          memberId: 'member_a1',
          status: 'attended',
          recordedBy: 'instructor_a',
          recordedAt: new Date(),
        }),
    );
  });

  it('um Instrutor CONSEGUE ler a presença (só leitura)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .set({
          memberId: 'member_a1',
          status: 'attended',
          recordedBy: 'manager_a',
          recordedAt: new Date(),
        });
    });

    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .get(),
    );
  });

  it('um membro NÃO consegue registar a própria presença', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .set({
          memberId: 'member_a1',
          status: 'attended',
          recordedBy: 'member_a1',
          recordedAt: new Date(),
        }),
    );
  });

  it('um membro NÃO consegue LER a própria presença (nem Instrutor/Manager sobre presença dão isso a um Aluno)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .set({
          memberId: 'member_a1',
          status: 'attended',
          recordedBy: 'manager_a',
          recordedAt: new Date(),
        });
    });

    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(
          `tenants/${TENANT_A}/freeTrainingSchedules/week_published/slots/slot_published/attendance/member_a1`,
        )
        .get(),
    );
  });
});
