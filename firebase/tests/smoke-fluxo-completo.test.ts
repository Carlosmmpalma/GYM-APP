// Fase 11 — teste de fumo do fluxo completo, contra os dados SEMEADOS.
//
// Escrito depois de um relato de "está tudo bugado" que se veio a
// revelar ambiente — um emulador zombie que segurava as portas e
// devolvia 404 em todas as funções. A app dizia "algo correu mal" e não
// havia forma rápida de distinguir "o código está partido" de "o
// servidor não está lá".
//
// É isso que este ficheiro resolve: corre o percurso que uma pessoa faz
// (gerar grelha de treino livre, publicar, marcar aula, cancelar) sobre
// o tenant real do seed, e falha depressa e de forma legível se o
// ambiente não estiver de pé.
//
// Corre-o quando algo "não funciona" na app, ANTES de procurar o bug no
// código:
//
//   npm --prefix firebase/tests test -- smoke

import { initializeApp as adminInit } from 'firebase-admin/app';
import { getAuth as adminAuth } from 'firebase-admin/auth';
import { getFirestore as adminDb } from 'firebase-admin/firestore';
import {
  deleteApp,
  initializeApp,
  type FirebaseApp,
} from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT = 'nxt_performance_studio';
const REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const admin = adminInit({ projectId: PROJECT_ID }, 'smoke-admin');
const db = adminDb(admin);
const apps: FirebaseApp[] = [];

let managerFns: Functions;
let memberFns: Functions;
let memberId: string;
let freeTrainingServiceId: string;

async function clientFor(name: string, uid: string, claims: object) {
  const app = initializeApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    name,
  );
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth(admin).createCustomToken(uid, claims),
  );
  const fns = getFunctions(app, REGION);
  connectFunctionsEmulator(fns, 'localhost', 5001);
  return fns;
}

/// Espelho de `toDomainLabel` em
/// `functions/src/lib/loginIdentifier.ts` e
/// `lib/core/config/login_identifier.dart`.
function toDomainLabel(tenantId: string): string {
  const collapsed = tenantId
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return collapsed === '' ? 'tenant' : collapsed;
}

beforeAll(async () => {
  const users = await adminAuth(admin).listUsers(50);
  const leo = users.users.find((u) => u.email === 'leo@nxtperformancestudio.pt');
  // O domínio do email sintético é derivado do `tenantId` e já mudou
  // uma vez: `nxt_performance_studio` virou `nxt-performance-studio`
  // quando se descobriu que o Firebase Auth real recusa `_` num
  // domínio. Este teste tinha o formato antigo escrito à mão.
  //
  // Filtrar só por `member-000001@` também não serve: o seed cria um
  // sócio nº 000001 em DOIS tenants (o real e o fantasma dos testes de
  // isolamento), e apanhava-se o que viesse primeiro. Deriva-se o
  // domínio pela mesma regra da app.
  const ritaEmail = `member-000001@${toDomainLabel('nxt_performance_studio')}.gymsaas.internal`;
  const rita = users.users.find((u) => u.email === ritaEmail);

  if (!leo || !rita) {
    throw new Error(
      'Contas do seed não encontradas. Corre `npm --prefix firebase/scripts ' +
        'run seed` antes deste teste.',
    );
  }

  memberId = rita.uid;
  managerFns = await clientFor('smoke-leo', leo.uid, leo.customClaims as object);
  memberFns = await clientFor('smoke-rita', rita.uid, rita.customClaims as object);

  const cfg = await db.doc(`tenants/${TENANT}/config/bookingPolicy`).get();
  freeTrainingServiceId = cfg.get('freeTrainingServiceId') as string;
}, 60_000);

afterAll(async () => {
  await Promise.all(apps.map((app) => deleteApp(app)));
});

describe('Fluxo completo sobre os dados do seed', () => {
  it('o seed deixou o estúdio configurado', () => {
    // Se isto falha, o resto vai falhar por arrasto — e a mensagem daqui
    // diz o que fazer.
    expect(freeTrainingServiceId).toBeTruthy();
  });

  it('o Gestor gera e publica a grelha de treino livre', async () => {
    const suggest = await httpsCallable(
      managerFns,
      'suggestFreeTrainingSchedule',
    )({
      weekStart: new Date().toISOString(),
      serviceId: freeTrainingServiceId,
    });
    const { weekId } = suggest.data as { weekId: string };
    expect(weekId).toBeTruthy();

    // A sugestão copia a semana anterior; na primeira semana do estúdio
    // não há nada para copiar e o rascunho nasce vazio. Publicar exige
    // pelo menos um bloco — por isso o Gestor acrescenta-os à mão, que
    // é exatamente o que a app faz com "Adicionar bloco de horário".
    const slots = await db
      .collection(`tenants/${TENANT}/freeTrainingSchedules/${weekId}/slots`)
      .get();
    if (slots.empty) {
      const start = new Date();
      start.setDate(start.getDate() + 1);
      start.setHours(10, 0, 0, 0);
      await db
        .collection(`tenants/${TENANT}/freeTrainingSchedules/${weekId}/slots`)
        .add({
          serviceId: freeTrainingServiceId,
          startAt: start,
          endAt: new Date(start.getTime() + 2 * 3600_000),
          capacity: 10,
          activeBookingCount: 0,
        });
    }

    await httpsCallable(managerFns, 'publishFreeTrainingSchedule')({ weekId });

    const schedule = await db
      .doc(`tenants/${TENANT}/freeTrainingSchedules/${weekId}`)
      .get();
    expect(schedule.get('status')).toBe('published');
  }, 30_000);

  it('a aluna marca e cancela uma aula', async () => {
    const occurrences = await db
      .collection(`tenants/${TENANT}/sessionOccurrences`)
      .where('serviceId', '==', 'group_classes_test')
      .orderBy('startAt')
      .limit(1)
      .get();
    expect(occurrences.empty).toBe(false);
    const occurrenceId = occurrences.docs[0].id;

    // Este teste corre sobre dados semeados e é para ser corrido vezes
    // sem conta. Limpar a marcação de uma execução anterior evita que
    // falhe com "já tens uma marcação" — que seria o teste a tropeçar
    // em si próprio, não um problema da app.
    const previous = db.doc(
      `tenants/${TENANT}/sessionOccurrences/${occurrenceId}/bookings/${memberId}`,
    );
    if ((await previous.get()).exists) {
      await previous.delete();
      await db
        .doc(`tenants/${TENANT}/sessionOccurrences/${occurrenceId}`)
        .update({ activeBookingCount: 0 });
    }

    // E a utilização semanal. O plano semeado dá 1 aula/semana; sem
    // repor o contador, a segunda execução do dia bate no limite — o
    // que é o comportamento CERTO da app, mas aqui só faria o teste de
    // fumo falhar por razões suas.
    const usage = await db
      .collection(`tenants/${TENANT}/usage`)
      .where('memberId', '==', memberId)
      .get();
    for (const doc of usage.docs) await doc.ref.delete();

    await httpsCallable(memberFns, 'createBooking')({
      occurrenceId,
      memberId,
    });
    let booking = await db
      .doc(
        `tenants/${TENANT}/sessionOccurrences/${occurrenceId}/bookings/${memberId}`,
      )
      .get();
    expect(booking.get('status')).toBe('booked');

    await httpsCallable(memberFns, 'cancelBooking')({ occurrenceId, memberId });
    booking = await db
      .doc(
        `tenants/${TENANT}/sessionOccurrences/${occurrenceId}/bookings/${memberId}`,
      )
      .get();
    expect(booking.get('status')).toBe('cancelled');
  }, 30_000);

  it('a subscrição da aluna dá acesso aos serviços do plano', async () => {
    // O bug que motivou `syncPlanSubscriptions`: a lista da subscrição
    // ficava presa no momento da criação.
    const subs = await db
      .collection(`tenants/${TENANT}/subscriptions`)
      .where('memberId', '==', memberId)
      .where('status', '==', 'active')
      .get();
    expect(subs.empty).toBe(false);

    const granted = subs.docs.flatMap(
      (d) => (d.get('activeServiceIds') as string[]) ?? [],
    );
    expect(granted).toContain('group_classes_test');
    expect(granted).toContain(freeTrainingServiceId);
  });
});
