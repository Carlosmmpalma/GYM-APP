// Fase 11 — registo de treino: quem pode registar o quê.
//
// Num ginásio com acompanhamento os três papéis registam: o aluno o seu
// próprio treino, e o instrutor ou o gestor por ele quando o acompanham
// ao lado. Até aqui o `loadHistory` era Instrutor/Gestor apenas, o que
// tornava impossível ao aluno registar o que fez — o caso normal, não a
// exceção.
//
// O que este ficheiro fixa:
//   1. Os três registam.
//   2. Um aluno não regista no treino de OUTRO.
//   3. O histórico não se reescreve (UC16), nem pelo próprio.
//   4. Uma sessão TERMINADA não se apaga; uma em curso sim.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const TENANT = 'tenant_sessions';
const RITA = 'member_rita';
const BRUNO = 'member_bruno';
const ANA = 'instructor_ana';
const LEO = 'manager_leo';

const RULES_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'firestore.rules',
);

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-gym-saas-dev-sessions-test',
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
    await db.doc(`tenants/${TENANT}`).set({ name: 'Estúdio' });
    for (const uid of [RITA, BRUNO]) {
      await db.doc(`tenants/${TENANT}/members/${uid}`).set({
        name: uid,
        memberNumber: '000001',
        status: 'active',
      });
    }
    // Uma sessão terminada, para testar que o histórico não se apaga.
    await db
      .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/terminada`)
      .set({
        workoutName: 'Treino A',
        startedAt: new Date(),
        finishedAt: new Date(),
        performedBy: RITA,
        sets: [],
      });
    // E uma em curso.
    await db
      .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/em_curso`)
      .set({
        workoutName: 'Treino B',
        startedAt: new Date(),
        finishedAt: null,
        performedBy: RITA,
        sets: [],
      });
  });
});

function as(uid: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId: TENANT, roles }).firestore();
}

const novaSessao = {
  workoutName: 'Treino A',
  startedAt: new Date(),
  finishedAt: null,
  performedBy: 'quem',
  sets: [],
};

describe('Sessões de treino — quem regista', () => {
  it('a própria aluna abre uma sessão', async () => {
    // O caso que as Rules antigas tornavam impossível.
    await assertSucceeds(
      as(RITA, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/nova`)
        .set(novaSessao),
    );
  });

  it('o Instrutor abre uma sessão pela aluna', async () => {
    // Acompanhamento: o instrutor regista ao lado dela.
    await assertSucceeds(
      as(ANA, ['instructor'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/nova`)
        .set(novaSessao),
    );
  });

  it('o Gestor também', async () => {
    await assertSucceeds(
      as(LEO, ['manager'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/nova`)
        .set(novaSessao),
    );
  });

  it('um aluno NÃO regista no treino de outro aluno', async () => {
    await assertFails(
      as(BRUNO, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/nova`)
        .set(novaSessao),
    );
  });

  it('um aluno NÃO lê as sessões de outro aluno', async () => {
    await assertFails(
      as(BRUNO, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/terminada`)
        .get(),
    );
  });

  it('a aluna lê as suas', async () => {
    await assertSucceeds(
      as(RITA, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/terminada`)
        .get(),
    );
  });
});

describe('Sessões de treino — o histórico é histórico', () => {
  it('descartar uma sessão EM CURSO é permitido', async () => {
    // Quem abre um treino por engano tem de o poder deitar fora.
    await assertSucceeds(
      as(RITA, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/em_curso`)
        .delete(),
    );
  });

  it('apagar uma sessão TERMINADA não é', async () => {
    // Um treino feito é registo. Apagá-lo passa pelo apagamento RGPD,
    // que é uma ação deliberada e auditável.
    await assertFails(
      as(RITA, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/terminada`)
        .delete(),
    );
  });

  it('nem sequer o Gestor apaga uma sessão terminada', async () => {
    await assertFails(
      as(LEO, ['manager'])
        .doc(`tenants/${TENANT}/members/${RITA}/workoutSessions/terminada`)
        .delete(),
    );
  });
});

describe('Histórico de cargas', () => {
  const registo = {
    exerciseId: 'supino',
    load: 60,
    reps: 8,
    recordedBy: RITA,
    recordedAt: new Date(),
  };

  it('a própria aluna regista uma carga', async () => {
    await assertSucceeds(
      as(RITA, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/loadHistory/r1`)
        .set(registo),
    );
  });

  it('um aluno NÃO regista cargas de outro', async () => {
    await assertFails(
      as(BRUNO, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/loadHistory/r1`)
        .set(registo),
    );
  });

  it('nunca se sobrescreve — nem o próprio (UC16)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT}/members/${RITA}/loadHistory/r1`)
        .set(registo);
    });

    await assertFails(
      as(RITA, ['member'])
        .doc(`tenants/${TENANT}/members/${RITA}/loadHistory/r1`)
        .update({ load: 999 }),
    );
    await assertFails(
      as(LEO, ['manager'])
        .doc(`tenants/${TENANT}/members/${RITA}/loadHistory/r1`)
        .delete(),
    );
  });
});
