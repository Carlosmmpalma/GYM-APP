// 🔴 Fase 3 — Security Rules para plans/plans.services/subscriptions/
// services.
//
// Cobre as invariantes novas nesta fase que não existiam em Fase 1/2:
//   1. Escrita em `plans` e `plans/{id}/services` só para Manager
//      (`isManager()`, firestore.rules) — leitura continua ampla dentro
//      do tenant, como em Fase 1/2.
//   2. `subscriptions` nunca é escrita pelo cliente, nem por um Manager
//      — a única via é a Cloud Function `createSubscription` (Admin
//      SDK, ignora Rules). Ver nota de arquitetura em
//      `firebase_subscription_repository.dart`.
//   3. `services` (Fase 2 tinha `allow write: if false` — nunca havia
//      ecrã de gestão) passou a aceitar escrita de Manager, agora que
//      `ManageServicesScreen` existe (correção feita depois de um
//      utilizador reportar que não conseguia criar Services).
// Isolamento entre tenants para estas coleções é a mesma regra
// (`belongsToTenant`) já coberta exaustivamente em
// `tenant-isolation.test.ts` — aqui só confirmamos que também se
// aplica às coleções novas, não repetimos todos os casos.
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
    // projectId próprio — mesmo motivo do comentário em
    // tenant-isolation.test.ts: ficheiros de teste correm em paralelo e
    // cada um faz clearFirestore(); partilhar projectId entre ficheiros
    // causa contaminação cruzada.
    projectId: 'demo-gym-saas-dev-plans-subscriptions-test',
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
    await db.doc(`tenants/${TENANT_A}/plans/plan_1`).set({
      name: 'Standard',
      description: '',
      currentPrice: 30,
      currency: 'EUR',
      active: true,
    });
    await db.doc(`tenants/${TENANT_A}/plans/plan_1/services/service_1`).set({
      serviceId: 'service_1',
      enabled: true,
      usage: { type: 'unlimited' },
    });
    await db.doc(`tenants/${TENANT_A}/subscriptions/sub_1`).set({
      memberId: 'member_a1',
      planId: 'plan_1',
      status: 'active',
      startDate: new Date(),
      agreedPrice: 30,
      currency: 'EUR',
      activeServiceIds: ['service_1'],
    });
    // Fase 11 — uma subscrição de OUTRO membro, para provar que um
    // aluno não lhe chega (o `agreedPrice` de cada pessoa é dela).
    await db.doc(`tenants/${TENANT_A}/subscriptions/sub_outro_membro`).set({
      memberId: 'member_a2',
      planId: 'plan_1',
      status: 'active',
      startDate: new Date(),
      agreedPrice: 75,
      currency: 'EUR',
      activeServiceIds: ['service_1'],
    });
    await db.doc(`tenants/${TENANT_A}/services/service_1`).set({
      name: 'Aula de Grupo',
      active: true,
    });

    await db.doc(`tenants/${TENANT_B}`).set({ name: 'Tenant B (fantasma)' });
  });
});

function contextFor(uid: string, tenantId: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

describe('Security Rules — plans (Fase 3, 🔴 crítico)', () => {
  it('um membro consegue LER os planos do próprio tenant', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/plans/plan_1`).get());
  });

  it('um membro NÃO consegue CRIAR um plano', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/plans/plan_2`).set({
        name: 'Intruso',
        description: '',
        currentPrice: 1,
        currency: 'EUR',
        active: true,
      }),
    );
  });

  it('um membro NÃO consegue ATUALIZAR um plano existente', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/plans/plan_1`).update({ currentPrice: 999 }),
    );
  });

  it('um Manager do tenant CONSEGUE criar um plano', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/plans/plan_2`).set({
        name: 'Premium',
        description: '',
        currentPrice: 60,
        currency: 'EUR',
        active: true,
      }),
    );
  });

  it('um Manager de OUTRO tenant NÃO consegue criar plano no tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/plans/plan_2`).set({
        name: 'Invasor',
        description: '',
        currentPrice: 1,
        currency: 'EUR',
        active: true,
      }),
    );
  });

  it('um membro NÃO consegue alterar os services de um plano', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/plans/plan_1/services/service_1`).update({
        enabled: false,
      }),
    );
  });

  it('um Manager CONSEGUE alterar os services de um plano', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/plans/plan_1/services/service_1`).update({
        enabled: false,
      }),
    );
  });
});

describe('Security Rules — services (Fase 3, correção)', () => {
  it('um membro consegue LER os services do próprio tenant', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/services/service_1`).get());
  });

  it('um membro NÃO consegue CRIAR um service', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/services/service_2`).set({
        name: 'Intruso',
        active: true,
      }),
    );
  });

  it('um Manager do tenant CONSEGUE criar um service', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/services/service_2`).set({
        name: 'Pilates',
        active: true,
      }),
    );
  });

  it('um Manager CONSEGUE desativar um service existente', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/services/service_1`).update({ active: false }),
    );
  });

  it('um Manager de OUTRO tenant NÃO consegue criar service no tenant A', async () => {
    const db = contextFor('manager_b', TENANT_B, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/services/service_2`).set({
        name: 'Invasor',
        active: true,
      }),
    );
  });
});

describe('Security Rules — subscriptions (Fase 3, 🔴 crítico)', () => {
  it('um membro consegue LER a SUA própria subscription', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/subscriptions/sub_1`).get());
  });

  // Fase 11 — até aqui a regra era `belongsToTenant(tenantId)` e
  // qualquer aluno lia as subscrições de TODOS os outros, com o
  // `agreedPrice` incluído: o preço que cada pessoa negociou, à vista de
  // toda a gente do ginásio. Encontrado ao ligar o filtro de
  // elegibilidade em "Marcar treino", que passou a ler subscrições a
  // partir do cliente do Aluno.
  it('um membro NÃO consegue ler a subscription de OUTRO membro', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/subscriptions/sub_outro_membro`).get(),
    );
  });

  it('um membro NÃO consegue listar as subscriptions todas', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(db.collection(`tenants/${TENANT_A}/subscriptions`).get());
  });

  it('mas CONSEGUE listar as suas, filtrando por memberId', async () => {
    // É esta a query que `myEligibleServiceIdsProvider` faz. Numa lista,
    // a regra é avaliada por documento devolvido: filtrada por
    // `memberId`, só devolve os próprios e passa.
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db
        .collection(`tenants/${TENANT_A}/subscriptions`)
        .where('memberId', '==', 'member_a1')
        .get(),
    );
  });

  it('um Instrutor continua a ler todas (pré-atribuição a sessões)',
    async () => {
      const db = contextFor('instructor_a', TENANT_A, ['instructor']).firestore();
      await assertSucceeds(
        db.collection(`tenants/${TENANT_A}/subscriptions`).get(),
      );
    });

  it('um membro de OUTRO tenant NÃO consegue ler subscriptions do tenant A', async () => {
    const db = contextFor('member_b1', TENANT_B, ['member']).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/subscriptions/sub_1`).get());
  });

  it('um membro NÃO consegue criar a própria subscription diretamente', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/subscriptions/sub_self_service`).set({
        memberId: 'member_a1',
        planId: 'plan_1',
        status: 'active',
        startDate: new Date(),
        agreedPrice: 0,
        currency: 'EUR',
        activeServiceIds: ['service_1'],
      }),
    );
  });

  it('nem um Manager consegue criar uma subscription diretamente (só via Cloud Function)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/subscriptions/sub_by_manager`).set({
        memberId: 'member_a1',
        planId: 'plan_1',
        status: 'active',
        startDate: new Date(),
        agreedPrice: 0,
        currency: 'EUR',
        activeServiceIds: ['service_1'],
      }),
    );
  });

  it('ninguém consegue apagar uma subscription', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(db.doc(`tenants/${TENANT_A}/subscriptions/sub_1`).delete());
  });
});
