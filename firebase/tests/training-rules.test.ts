// 🔴 Fase 8 — Security Rules de avaliações/histórico de carga/plano de
// treino/biblioteca de exercícios (UC04/UC14/UC16/UC13/UC15).
//   1. `assessments`/`loadHistory`/`planEntries` (subcoleções de
//      members/{memberId}) — o próprio membro só LÊ o seu; Instrutor/
//      Gestor leem e escrevem; outro membro nunca lê nada disto.
//   2. `loadHistory` — só `create` (UC16 fechado: "nunca sobrescrever
//      o histórico"), `update`/`delete` sempre `false`, mesmo para
//      Manager.
//   3. `exercises` — biblioteca partilhada: leitura ampla no tenant,
//      escrita Instrutor OU Gestor (não Manager-only, ao contrário de
//      services/plans/modalities).
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
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const TENANT_A = 'tenant_a_real';
const TENANT_B = 'tenant_b_ghost';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-gym-saas-dev-training-test',
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
    // Fase 11 (RGPD) — escrever avaliações e cargas passou a exigir
    // consentimento explícito do membro (artigo 9.º). Estes testes são
    // sobre PERMISSÕES POR ROLE, por isso o membro semeado é um que
    // autorizou; o caso de quem não autorizou está em `gdpr.test.ts`,
    // que verifica que nem um Instrutor consegue escrever.
    await db.doc(`tenants/${TENANT_A}/members/member_a1`).set({
      consent: { privacyPolicyVersion: 1, healthDataGranted: true },
      memberNumber: '000001',
      name: 'Rita Ferreira',
      status: 'active',
    });
    await db.doc(`tenants/${TENANT_A}/members/member_a2`).set({
      memberNumber: '000002',
      name: 'Outro Membro',
      status: 'active',
    });

    await db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_1`).set({
      instructorId: 'instructor_a',
      createdAt: new Date(),
      idade: 30,
      peso: 70,
      altura: 1.75,
    });
    await db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_1`).set({
      exerciseId: 'exercise_1',
      load: 60,
      reps: 8,
      recordedAt: new Date(),
      recordedBy: 'instructor_a',
    });
    await db.doc(`tenants/${TENANT_A}/members/member_a1/planEntries/plan_1`).set({
      exerciseId: 'exercise_1',
      sets: 4,
      reps: 8,
      currentLoad: 60,
    });
    await db.doc(`tenants/${TENANT_A}/exercises/exercise_1`).set({
      name: 'Agachamento com barra',
      description: '',
      muscleGroup: 'Pernas',
      videoPath: null,
    });

    await db.doc(`tenants/${TENANT_B}`).set({ name: 'Tenant B (fantasma)' });
  });
});

function contextFor(uid: string, tenantId: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

describe('Security Rules — assessments (Fase 8, UC04/UC14 fechado)', () => {
  it('o próprio membro CONSEGUE ler as suas avaliações', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_1`).get(),
    );
  });

  it('um membro NÃO consegue ler as avaliações de OUTRO membro', async () => {
    const db = contextFor('member_a2', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_1`).get(),
    );
  });

  it('um membro NÃO consegue criar/editar a própria avaliação — só o Instrutor/Gestor avalia', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_2`).set({
        instructorId: 'member_a1',
        createdAt: new Date(),
        idade: 30,
      }),
    );
  });

  it('um Instrutor CONSEGUE criar e ler avaliações', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_2`).set({
        instructorId: 'instructor_a',
        createdAt: new Date(),
        idade: 31,
      }),
    );
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_1`).get(),
    );
  });

  it('um Gestor CONSEGUE editar uma avaliação já existente (UC04/UC14: "pode corrigir")',
    async () => {
      const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
      await assertSucceeds(
        db.doc(`tenants/${TENANT_A}/members/member_a1/assessments/assessment_1`).update({
          updatedBy: 'manager_a',
          updatedAt: new Date(),
          peso: 71,
        }),
      );
    },
  );
});

describe('Security Rules — loadHistory (Fase 8, UC16 fechado: "nunca sobrescrever")', () => {
  it('o próprio membro CONSEGUE ler o seu histórico de carga', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_1`).get(),
    );
  });

  it('um membro NÃO consegue ler o histórico de OUTRO membro', async () => {
    const db = contextFor('member_a2', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_1`).get(),
    );
  });

  it('um Instrutor CONSEGUE criar um novo registo de carga', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_2`).set({
        exerciseId: 'exercise_1',
        load: 62.5,
        reps: 8,
        recordedAt: new Date(),
        recordedBy: 'instructor_a',
      }),
    );
  });

  it('nem um Gestor consegue ALTERAR um registo já existente — histórico é imutável', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_1`).update({
        load: 999,
      }),
    );
  });

  it('nem um Gestor consegue APAGAR um registo já existente', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_1`).delete(),
    );
  });

  // Fase 11 — este teste afirmava o CONTRÁRIO, e a mudança é
  // deliberada. Na Fase 8 só o Instrutor registava cargas, porque não
  // havia registo de treino: o aluno não tinha por onde o fazer. Com as
  // sessões de treino, o aluno regista o que fez — num ginásio isso é o
  // caso normal, não a exceção.
  //
  // O que continua a valer, e é o que esta secção protege de facto: um
  // aluno só escreve no SEU histórico. Coberto aqui e em
  // `workout-sessions-rules.test.ts`.
  it('um membro cria um registo de carga no SEU histórico', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_2`).set({
        exerciseId: 'exercise_1',
        load: 60,
        reps: 8,
        recordedAt: new Date(),
        recordedBy: 'member_a1',
      }),
    );
  });

  it('um membro NÃO cria um registo no histórico de OUTRO', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a2/loadHistory/entry_9`).set({
        exerciseId: 'exercise_1',
        load: 999,
        reps: 8,
        recordedAt: new Date(),
        recordedBy: 'member_a1',
      }),
    );
  });
});

// Fase 11 (reportado a testar) — corrigir uma série mal registada.
//
// O registo ao vivo escreve um registo de carga por série. Escrever 6
// em vez de 60 deixava um ponto errado na evolução da carga PARA
// SEMPRE, porque `loadHistory` era imutável de ponta a ponta.
//
// A abertura é estreita de propósito: só `delete`, e só em registos que
// vieram de uma série (`sessionId` presente). Corrigir é apagar o
// errado e criar o certo; alterá-lo no lugar seria mesmo reescrever
// histórico.
describe('Security Rules — corrigir uma série (Fase 11)', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/from_session`)
        .set({
          exerciseId: 'exercise_1',
          load: 6,
          reps: 8,
          recordedAt: new Date(),
          recordedBy: 'member_a1',
          sessionId: 'session_1',
        });
    });
  });

  it('o próprio membro apaga o registo criado por uma série sua', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db
        .doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/from_session`)
        .delete(),
    );
  });

  it('o Instrutor também apaga — é ele quem regista ao lado do aluno',
    async () => {
      const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
      await assertSucceeds(
        db
          .doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/from_session`)
          .delete(),
      );
    });

  it('um registo SEM sessionId continua imutável', async () => {
    // `entry_1` é o registo que o Instrutor cria ao mudar a carga
    // prescrita. Essa é a progressão que o UC16 protege, e continua a
    // não se poder apagar.
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/entry_1`).delete(),
    );
  });

  it('nem o registo de sessão se pode ALTERAR no lugar', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/from_session`)
        .update({ load: 60 }),
    );
  });

  it('um membro NÃO apaga uma série do histórico de outro', async () => {
    const db = contextFor('member_a2', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/members/member_a1/loadHistory/from_session`)
        .delete(),
    );
  });
});

describe('Security Rules — planEntries (Fase 8, UC13)', () => {
  it('o próprio membro CONSEGUE ler o seu plano', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/planEntries/plan_1`).get(),
    );
  });

  it('um membro NÃO consegue ler o plano de OUTRO membro', async () => {
    const db = contextFor('member_a2', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/member_a1/planEntries/plan_1`).get(),
    );
  });

  it('um membro NÃO consegue editar o próprio plano — só Instrutor/Gestor monta o plano',
    async () => {
      const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
      await assertFails(
        db.doc(`tenants/${TENANT_A}/members/member_a1/planEntries/plan_1`).update({
          currentLoad: 999,
        }),
      );
    },
  );

  it('um Instrutor CONSEGUE editar o plano', async () => {
    const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1/planEntries/plan_1`).update({
        currentLoad: 62.5,
      }),
    );
  });
});

describe('Security Rules — exercises (Fase 8, UC15 fechado: "partilhada por todos os instrutores")', () => {
  it('um membro consegue LER a biblioteca (precisa de ver os exercícios do seu plano)',
    async () => {
      const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
      await assertSucceeds(db.doc(`tenants/${TENANT_A}/exercises/exercise_1`).get());
    },
  );

  it('um membro NÃO consegue criar um exercício', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/exercises/exercise_2`).set({
        name: 'Sled Push',
        description: '',
        muscleGroup: 'Hyrox',
        videoPath: null,
      }),
    );
  });

  it('um Instrutor CONSEGUE criar/editar um exercício (biblioteca partilhada, não Manager-only)',
    async () => {
      const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
      await assertSucceeds(
        db.doc(`tenants/${TENANT_A}/exercises/exercise_2`).set({
          name: 'Sled Push',
          description: '',
          muscleGroup: 'Hyrox',
          videoPath: null,
        }),
      );
    },
  );

  it('um Instrutor de OUTRO tenant NÃO consegue criar exercício no tenant A', async () => {
    const db = contextFor('instructor_b', TENANT_B, ['instructor']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/exercises/exercise_intruder`).set({
        name: 'Sled Push',
        description: '',
        muscleGroup: 'Hyrox',
        videoPath: null,
      }),
    );
  });
});
