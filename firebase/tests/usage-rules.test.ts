// 🔴 Fase 4 — Security Rules para usage tracking + fecho de escrita
// client-side em bookings/sessionOccurrences/config.
//
// Cobre as invariantes novas nesta fase:
//   1. `usage/{usageId}` — leitura ampla dentro do tenant (a barra "X/Y
//      sessões esta semana" lê isto do lado do próprio membro), escrita
//      SEMPRE negada ao cliente (só `createBooking`/`cancelBooking`/
//      `recalculateUsage`, Admin SDK, escrevem — ver createBooking.ts).
//   2. `bookings`/`sessionOccurrences` — até à Fase 3, o próprio membro
//      conseguia escrever diretamente (transação client-side, Fase 2).
//      A partir desta fase, ESCREVER fica `false` para QUALQUER cliente,
//      incluindo o dono da marcação — só a Cloud Function escreve.
//      Isto fecha, de vez, a lacuna já documentada no código antigo
//      (`firebase_booking_repository.dart`, nota removida nesta fase):
//      um cliente malicioso já não consegue, nem em teoria, escrever só
//      o incremento do contador sem criar o booking.
//   3. `config/{configId}` — escrita passou de "qualquer membro do
//      tenant" (Fase 1, quando só guardava dados genéricos) para "só
//      Manager" (Fase 4: `bookingPolicy.minCancellationNoticeHours` é
//      uma decisão de negócio do Gestor).
//
// Isolamento entre tenants para `usage` é a mesma regra
// (`belongsToTenant`) já coberta exaustivamente em
// `tenant-isolation.test.ts` — aqui só confirmamos que também se aplica
// à coleção nova.
//
// Precisa do emulador do Firestore a correr. Corre com, a partir da
// raiz do projeto (onde está o firebase.json):
//   firebase emulators:exec --only firestore "npm --prefix firebase/tests test"
//
// Não corri isto neste ambiente — sem Java (nem, portanto, o emulador
// do Firestore) disponível na sandbox onde este código foi escrito (ver
// README.md, "Ainda em aberto" da Fase 4).

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
    projectId: 'demo-gym-saas-dev-usage-test',
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
    await db.doc(`tenants/${TENANT_A}/usage/member_a1_service_1_2026-W01`).set({
      memberId: 'member_a1',
      serviceId: 'service_1',
      period: '2026-W01',
      periodType: 'week',
      used: 1,
    });
    await db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).set({
      serviceId: 'service_1',
      startAt: new Date(),
      endAt: new Date(),
      capacity: 2,
      status: 'scheduled',
      activeBookingCount: 0,
    });
    await db
      .doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/bookings/member_a1`)
      .set({
        memberId: 'member_a1',
        status: 'booked',
        source: 'self',
        isExtra: false,
        serviceId: 'service_1',
        period: '2026-W01',
        createdAt: new Date(),
      });

    await db.doc(`tenants/${TENANT_B}`).set({ name: 'Tenant B (fantasma)' });
  });
});

function contextFor(uid: string, tenantId: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

describe('Security Rules — usage (Fase 4, 🔴 crítico)', () => {
  it('o próprio membro consegue LER o seu usage', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/usage/member_a1_service_1_2026-W01`).get(),
    );
  });

  it('um Manager consegue LER usage de qualquer membro do tenant', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/usage/member_a1_service_1_2026-W01`).get(),
    );
  });

  it('um membro de OUTRO tenant NÃO consegue ler usage do tenant A', async () => {
    const db = contextFor('member_b1', TENANT_B, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/usage/member_a1_service_1_2026-W01`).get(),
    );
  });

  it('o próprio membro NÃO consegue escrever usage diretamente', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/usage/member_a1_service_1_2026-W01`).update({
        used: 999,
      }),
    );
  });

  it('nem um Manager consegue escrever usage diretamente (só via Cloud Function)', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/usage/member_a1_service_1_2026-W01`).update({
        used: 0,
      }),
    );
  });
});

describe('Security Rules — bookings/sessionOccurrences (Fase 4: escrita fechada ao cliente)', () => {
  it('o dono da marcação já NÃO consegue cancelar diretamente (era permitido até à Fase 3)', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/bookings/member_a1`)
        .update({ status: 'cancelled' }),
    );
  });

  it('o dono da marcação já NÃO consegue criar uma marcação diretamente', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/bookings/member_a2`)
        .set({
          memberId: 'member_a2',
          status: 'booked',
          source: 'self',
          isExtra: false,
          serviceId: 'service_1',
          period: '2026-W01',
          createdAt: new Date(),
        }),
    );
  });

  it('ninguém consegue escrever activeBookingCount diretamente (nem dentro dos limites válidos)', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).update({
        activeBookingCount: 1,
      }),
    );
  });

  it('leitura continua ampla dentro do tenant (mostrar vagas/marcações)', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1`).get());
    await assertSucceeds(
      db.doc(`tenants/${TENANT_A}/sessionOccurrences/occ_1/bookings/member_a1`).get(),
    );
  });
});

describe('Security Rules — config/bookingPolicy (Fase 4: escrita passa a Manager-only)', () => {
  it('um membro consegue LER a política de cancelamento', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc(`tenants/${TENANT_A}/config/bookingPolicy`)
        .set({ minCancellationNoticeHours: 24 });
    });
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertSucceeds(db.doc(`tenants/${TENANT_A}/config/bookingPolicy`).get());
  });

  it('um membro NÃO consegue alterar a política de cancelamento', async () => {
    const db = contextFor('member_a1', TENANT_A, ['member']).firestore();
    await assertFails(
      db
        .doc(`tenants/${TENANT_A}/config/bookingPolicy`)
        .set({ minCancellationNoticeHours: 0 }),
    );
  });

  it('um Manager CONSEGUE alterar a política de cancelamento', async () => {
    const db = contextFor('manager_a', TENANT_A, ['manager']).firestore();
    await assertSucceeds(
      db
        .doc(`tenants/${TENANT_A}/config/bookingPolicy`)
        .set({ minCancellationNoticeHours: 24 }),
    );
  });
});
