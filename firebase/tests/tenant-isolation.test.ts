// 🔴 Teste crítico da Fase 1 (guia-desenvolvimento.md):
//
//   "Escrever testes no Emulator Suite que tentam ativamente ler/escrever
//    dados de outro tenant e confirmam que falham. Não avances da fase
//    sem isto."
//
// Não depende do seed script (firebase/scripts/seed.mjs) nem de nenhum
// utilizador Firebase Auth real — @firebase/rules-unit-testing permite
// construir contextos autenticados com claims arbitrários diretamente,
// o que torna este teste autossuficiente e repetível em CI.
//
// Precisa do emulador do Firestore a correr. Corre com, a partir da
// raiz do projeto (onde está o firebase.json):
//   firebase emulators:exec --only firestore "npm --prefix firebase/tests test"
//
// Não corri isto neste ambiente — sem acesso a npm registry/Firebase
// CLI aqui (ver README.md).

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
    // projectId distinto de booking-concurrency.test.ts DE PROPÓSITO: o
    // vitest corre ficheiros de teste em paralelo por omissão, e os dois
    // ficheiros chamam testEnv.clearFirestore() em cada teste. Se
    // partilhassem o mesmo projectId, estariam a apagar o Firestore
    // emulado um ao outro a meio da execução (foi isto que causou
    // "Transaction lock timeout" aqui e marcações "rejeitadas" sem
    // motivo de negócio no outro ficheiro). O emulador do Firestore
    // aceita qualquer projectId `demo-*` sem credenciais, por isso isto
    // não tem custo nenhum — só isola os dois ficheiros um do outro.
    projectId: 'demo-gym-saas-dev-isolation-test',
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
  // Popula os dois tenants com Admin SDK (ignora as Security Rules —
  // é só fixture, não faz parte do que estamos a testar).
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`tenants/${TENANT_A}`).set({ name: 'Tenant A (real)' });
    await db.doc(`tenants/${TENANT_A}/members/member_a1`).set({
      name: 'Membro do Tenant A',
    });
    // Fase 11 — um SEGUNDO membro do mesmo ginásio, para testar que um
    // aluno não alcança os dados do outro.
    await db.doc(`tenants/${TENANT_A}/members/member_a2`).set({
      name: 'Outro membro do Tenant A',
      nif: '123456789',
    });
    await db.doc(`tenants/${TENANT_B}`).set({ name: 'Tenant B (fantasma)' });
    await db.doc(`tenants/${TENANT_B}/members/member_b1`).set({
      name: 'Membro do Tenant B',
    });
  });
});

function contextFor(uid: string, tenantId: string, roles: string[] = ['member']) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

describe('Isolamento entre tenants (Fase 1, 🔴 crítico)', () => {
  it('um membro consegue ler dados do PRÓPRIO tenant', async () => {
    // Fase 11 — lia o documento de OUTRO membro (`user_a` a ler
    // `member_a1`). Passava por a regra ser `belongsToTenant`, que era
    // precisamente o problema: provava acesso ao tenant e escondia a
    // falta de privacidade entre alunos. Agora lê o SEU, que é o que
    // este teste sempre quis dizer.
    const db = contextFor('member_a1', TENANT_A).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/members/member_a1`).get());
  });

  it('um membro do tenant B NÃO consegue LER dados do tenant A', async () => {
    const db = contextFor('user_b', TENANT_B).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/members/member_a1`).get());
  });

  it('um membro do tenant A NÃO consegue LER dados do tenant B (simétrico)', async () => {
    const db = contextFor('user_a', TENANT_A).firestore();
    await assertFails(db.doc(`tenants/${TENANT_B}/members/member_b1`).get());
  });

  it('um membro do tenant B NÃO consegue ESCREVER no tenant A', async () => {
    const db = contextFor('user_b', TENANT_B).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/members/intruder`).set({ name: 'Invasor' }),
    );
  });

  it('um membro do tenant B NÃO consegue APAGAR dados do tenant A', async () => {
    const db = contextFor('user_b', TENANT_B).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/members/member_a1`).delete());
  });

  it('um utilizador não autenticado não lê nenhum tenant', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/members/member_a1`).get());
  });

  it('o documento raiz do tenant também está isolado, não só as subcollections', async () => {
    const db = contextFor('user_b', TENANT_B).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}`).get());
  });

  it('um claim tenantId inventado (sem corresponder a nenhum tenant real) continua sem acesso a tenants existentes', async () => {
    const db = contextFor('user_x', 'tenant_que_nao_existe').firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/members/member_a1`).get());
  });
});

// Fase 11 — encontrado a redigir a política de privacidade: a regra de
// `members` era `belongsToTenant(tenantId)`, ou seja qualquer aluno lia
// o documento de qualquer outro membro do MESMO ginásio — com NIF,
// morada, data de nascimento e contacto de emergência. O isolamento
// entre ginásios estava certo; o isolamento ENTRE ALUNOS não existia.
describe('Security Rules — privacidade entre alunos do mesmo ginásio', () => {
  it('um membro lê o SEU próprio documento', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/members/member_a1`).get(),
    );
  });

  it('um membro NÃO lê o documento de outro membro', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/members/member_a2`).get());
  });

  it('um membro NÃO lista os membros do ginásio', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(db.collection(`tenants/${TENANT_A}/members`).get());
  });

  it('um Instrutor lista os membros — precisa deles para dar aulas',
    async () => {
      const db = contextFor('instructor_a', TENANT_A, ['instructor'])
        .firestore();
      await assertSucceeds(db.collection(`tenants/${TENANT_A}/members`).get());
    });

  it('um Gestor lista os membros', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(db.collection(`tenants/${TENANT_A}/members`).get());
  });
});
