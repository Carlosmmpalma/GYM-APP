// Fase 11 — o Instrutor passou a poder criar as SUAS aulas.
//
// Até aqui séries e ocorrências eram Manager-only: num estúdio onde cada
// instrutor sabe as suas horas melhor do que ninguém, isso obrigava o
// Gestor a montar o horário de toda a gente.
//
// O que interessa testar não é o caminho feliz — são as fronteiras:
//
//   1. Só cria aulas dos serviços que o Gestor lhe associou.
//   2. Só as cria em NOME PRÓPRIO, nunca em nome de um colega.
//   3. Não pega numa série alheia para a reatribuir a si.
//   4. Um instrutor sem serviços associados não cria nada.

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

const TENANT = 'tenant_instructor_sessions';
const RULES_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'firestore.rules',
);

const ANA = 'instructor_ana';
const BRUNO = 'instructor_bruno';
const SEM_SERVICOS = 'instructor_novo';

const PILATES = 'service_pilates';
const HYROX = 'service_hyrox';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    // projectId próprio — ficheiros de teste correm em paralelo e cada
    // um faz clearFirestore().
    projectId: 'demo-gym-saas-dev-instructor-sessions-test',
    firestore: { rules: readFileSync(RULES_PATH, 'utf8'), host: 'localhost', port: 8080 },
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

    await db.doc(`tenants/${TENANT}/services/${PILATES}`).set({
      name: 'Pilates',
      active: true,
    });
    await db.doc(`tenants/${TENANT}/services/${HYROX}`).set({
      name: 'Hyrox',
      active: true,
    });

    // A Ana dá Pilates. O Bruno dá Hyrox. O terceiro ainda não tem nada
    // associado — é o estado em que um instrutor nasce.
    await db.doc(`tenants/${TENANT}/staff/${ANA}`).set({
      name: 'Ana',
      roles: ['instructor'],
      status: 'active',
      serviceIds: [PILATES],
    });
    await db.doc(`tenants/${TENANT}/staff/${BRUNO}`).set({
      name: 'Bruno',
      roles: ['instructor'],
      status: 'active',
      serviceIds: [HYROX],
    });
    await db.doc(`tenants/${TENANT}/staff/${SEM_SERVICOS}`).set({
      name: 'Novo',
      roles: ['instructor'],
      status: 'active',
    });

    // Uma série do Bruno, para testar que a Ana não lhe mexe.
    await db.doc(`tenants/${TENANT}/sessionSeries/serie_do_bruno`).set({
      serviceId: HYROX,
      instructorId: BRUNO,
      dayOfWeek: 1,
      startTime: '18:00',
      durationMinutes: 60,
      capacity: 8,
      status: 'active',
    });
  });
});

function as(uid: string, roles: string[] = ['instructor']) {
  return testEnv.authenticatedContext(uid, { tenantId: TENANT, roles }).firestore();
}

function serieDe(instructorId: string, serviceId: string) {
  return {
    serviceId,
    instructorId,
    dayOfWeek: 3,
    startTime: '10:00',
    durationMinutes: 60,
    capacity: 10,
    status: 'active',
  };
}

describe('Séries — Instrutor cria as suas', () => {
  it('a Ana cria uma série de Pilates, que é o serviço dela', async () => {
    await assertSucceeds(
      as(ANA).doc(`tenants/${TENANT}/sessionSeries/nova`).set(serieDe(ANA, PILATES)),
    );
  });

  it('a Ana NÃO cria uma série de Hyrox — não é serviço dela', async () => {
    await assertFails(
      as(ANA).doc(`tenants/${TENANT}/sessionSeries/nova`).set(serieDe(ANA, HYROX)),
    );
  });

  it('a Ana NÃO cria uma série em nome do Bruno', async () => {
    // Sem esta trava, um instrutor punha aulas no horário em nome de um
    // colega — que depois apareciam no calendário dele.
    await assertFails(
      as(ANA).doc(`tenants/${TENANT}/sessionSeries/nova`).set(serieDe(BRUNO, PILATES)),
    );
  });

  it('um instrutor SEM serviços associados não cria nada', async () => {
    // É o estado em que um instrutor nasce: o Gestor tem de decidir
    // primeiro o que ele pode lecionar.
    await assertFails(
      as(SEM_SERVICOS)
        .doc(`tenants/${TENANT}/sessionSeries/nova`)
        .set(serieDe(SEM_SERVICOS, PILATES)),
    );
  });

  it('um aluno não cria séries, com ou sem serviço', async () => {
    await assertFails(
      as('member_1', ['member'])
        .doc(`tenants/${TENANT}/sessionSeries/nova`)
        .set(serieDe('member_1', PILATES)),
    );
  });

  it('o Gestor continua a criar para quem quiser', async () => {
    await assertSucceeds(
      as('manager_1', ['manager'])
        .doc(`tenants/${TENANT}/sessionSeries/nova`)
        .set(serieDe(BRUNO, HYROX)),
    );
  });
});

describe('Séries — fronteiras na alteração', () => {
  it('o Bruno altera a série dele', async () => {
    await assertSucceeds(
      as(BRUNO)
        .doc(`tenants/${TENANT}/sessionSeries/serie_do_bruno`)
        .update({ capacity: 12 }),
    );
  });

  it('a Ana NÃO altera a série do Bruno', async () => {
    await assertFails(
      as(ANA)
        .doc(`tenants/${TENANT}/sessionSeries/serie_do_bruno`)
        .update({ capacity: 12 }),
    );
  });

  it('a Ana NÃO se apodera da série do Bruno reatribuindo-a a si',
    async () => {
      // A regra avalia a série que JÁ LÁ ESTÁ e a que fica. Só com as
      // duas é que este caso é apanhado: o estado final seria válido
      // para a Ana, mas ela não tinha direito ao estado inicial.
      await assertFails(
        as(ANA)
          .doc(`tenants/${TENANT}/sessionSeries/serie_do_bruno`)
          .update({ instructorId: ANA, serviceId: PILATES }),
      );
    });

  it('um instrutor NÃO apaga séries — nem as suas', async () => {
    // Apagar uma série com ocorrências geradas e alunos inscritos tem
    // consequências em cadeia; fica com o Gestor.
    await assertFails(
      as(BRUNO).doc(`tenants/${TENANT}/sessionSeries/serie_do_bruno`).delete(),
    );
  });
});

describe('Ocorrências avulsas — mesmas fronteiras', () => {
  function ocorrenciaDe(instructorId: string, serviceId: string) {
    return {
      serviceId,
      instructorId,
      startAt: new Date('2026-09-01T10:00:00Z'),
      endAt: new Date('2026-09-01T11:00:00Z'),
      capacity: 10,
      status: 'scheduled',
      activeBookingCount: 0,
    };
  }

  it('a Ana cria uma sessão avulsa de Pilates', async () => {
    await assertSucceeds(
      as(ANA)
        .doc(`tenants/${TENANT}/sessionOccurrences/nova`)
        .set(ocorrenciaDe(ANA, PILATES)),
    );
  });

  it('a Ana NÃO cria uma sessão de Hyrox', async () => {
    await assertFails(
      as(ANA)
        .doc(`tenants/${TENANT}/sessionOccurrences/nova`)
        .set(ocorrenciaDe(ANA, HYROX)),
    );
  });

  it('nem o Instrutor pode nascer com marcações já feitas', async () => {
    // `activeBookingCount == 0` na criação continua a valer para todos:
    // marcações só existem através das Cloud Functions.
    await assertFails(
      as(ANA)
        .doc(`tenants/${TENANT}/sessionOccurrences/nova`)
        .set({ ...ocorrenciaDe(ANA, PILATES), activeBookingCount: 3 }),
    );
  });
});
