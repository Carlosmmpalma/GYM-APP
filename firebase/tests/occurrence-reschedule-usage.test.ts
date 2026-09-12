// Mudar a HORA de uma aula que já tem inscritos.
//
// O estúdio edita uma aula pelo ecrã de gestão — é uma escrita direta do
// cliente sobre `sessionOccurrences`, e só toca no documento da aula. As
// marcações que já lá estão ficam como estavam.
//
// Isso parece inofensivo e não é. Cada marcação guarda uma cópia da
// `startAt` e o `period` (a semana ISO) em que foi contada, e o limite
// semanal do plano vive num documento
// `usage/{membro}_{serviço}_{semana}`. Mover uma aula para outra semana
// deixa a utilização contada na semana errada — e a semana de destino
// fica outra vez livre.
//
// Estes testes medem o tamanho do problema. Ficam a valer depois da
// correção: passam a provar que ela funciona.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import {
  getFirestore as getAdminFirestore,
  Timestamp,
} from 'firebase-admin/firestore';
import {
  deleteApp,
  initializeApp as initializeClientApp,
  type FirebaseApp,
} from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_remarcar_usage';
const SERVICE_ID = 'svc_aulas';
const PLAN_ID = 'plan_1x';
const MEMBER = 'ru_aluno';
const MANAGER = 'ru_gestor';
const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-remarcar');
const adminAuth = getAdminAuth(adminApp);
const db = getAdminFirestore(adminApp);
const tenantRef = db.doc(`tenants/${TENANT_ID}`);

const clientApps: FirebaseApp[] = [];
let memberFns: Functions;
let managerFns: Functions;

async function clientFor(uid: string, roles: string[]) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    `ru-${uid}`,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const fns = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(fns, 'localhost', 5001);
  return fns;
}

/** Uma quarta-feira às 19:00, daqui a `semanas` semanas — sempre futura. */
function quarta(semanas: number) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + ((3 - d.getUTCDay() + 7) % 7) + 7 * (semanas + 1));
  d.setUTCHours(19, 0, 0, 0);
  return d;
}

function bookingRef(occurrenceId: string) {
  return tenantRef
    .collection('sessionOccurrences')
    .doc(occurrenceId)
    .collection('bookings')
    .doc(MEMBER);
}

async function criarAula(id: string, quando: Date) {
  await tenantRef.collection('sessionOccurrences').doc(id).set({
    serviceId: SERVICE_ID,
    instructorId: null,
    modalityId: null,
    seriesId: null,
    startAt: Timestamp.fromDate(quando),
    endAt: Timestamp.fromDate(new Date(quando.getTime() + 3600_000)),
    capacity: 10,
    status: 'scheduled',
    activeBookingCount: 0,
    reminderSentAt: null,
  });
}

async function usagesDoMembro() {
  const s = await tenantRef
    .collection('usage')
    .where('memberId', '==', MEMBER)
    .get();
  return s.docs
    .map((d) => ({ periodo: d.get('period') as string, usado: d.get('used') as number }))
    .filter((u) => u.usado > 0);
}

beforeAll(async () => {
  await db.recursiveDelete(tenantRef);
  await tenantRef.set({ name: 'Estúdio', timeZone: 'Europe/Lisbon' });
  await tenantRef
    .collection('services')
    .doc(SERVICE_ID)
    .set({ name: 'Aula de Grupo', active: true });
  await tenantRef
    .collection('plans')
    .doc(PLAN_ID)
    .set({ name: '1x por semana', active: true, currentPrice: 30 });
  // Uma utilização por semana: é o que torna o problema visível.
  await tenantRef
    .collection('plans')
    .doc(PLAN_ID)
    .collection('services')
    .doc(SERVICE_ID)
    .set({
      serviceId: SERVICE_ID,
      enabled: true,
      usage: { type: 'limited', limit: 1 },
    });
  await tenantRef.collection('members').doc(MEMBER).set({
    name: 'Aluno',
    memberNumber: '000001',
    status: 'active',
  });
  await tenantRef.collection('subscriptions').doc('sub_1').set({
    memberId: MEMBER,
    planId: PLAN_ID,
    status: 'active',
    activeServiceIds: [SERVICE_ID],
  });

  for (const uid of [MEMBER, MANAGER]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }
  memberFns = await clientFor(MEMBER, ['member']);
  managerFns = await clientFor(MANAGER, ['manager']);
}, 60_000);

afterAll(async () => {
  await db.recursiveDelete(tenantRef);
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

beforeEach(async () => {
  for (const col of ['sessionOccurrences', 'usage']) {
    const s = await tenantRef.collection(col).get();
    await Promise.all(s.docs.map((d) => db.recursiveDelete(d.ref)));
  }
});

/** Move a aula pela Cloud Function, como o ecrã de gestão faz. */
async function moverAula(id: string, novaHora: Date) {
  await httpsCallable(managerFns, 'updateOccurrenceSchedule')({
    occurrenceId: id,
    startAt: novaHora.toISOString(),
    endAt: new Date(novaHora.getTime() + 3600_000).toISOString(),
    capacity: 10,
  });
}

describe('mudar a hora de uma aula com inscritos', () => {
  it('a utilização acompanha a aula para a semana nova', async () => {
    await criarAula('occ_a', quarta(0));
    await httpsCallable(memberFns, 'createBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER,
    });

    const antes = await usagesDoMembro();
    expect(antes).toHaveLength(1);
    const semanaOriginal = antes[0].periodo;

    await moverAula('occ_a', quarta(1));

    const depois = await usagesDoMembro();
    // Uma só utilização, e na semana onde a aula acontece agora.
    expect(depois).toHaveLength(1);
    expect(depois[0].usado).toBe(1);
    expect(depois[0].periodo).not.toBe(semanaOriginal);
  });

  it('e por isso o limite do plano continua a valer', async () => {
    // Este é o custo real do problema: não era um número errado num
    // ecrã, era o limite semanal a deixar de existir. Com 1x por semana,
    // mover a aula para a semana seguinte devolvia ao aluno a semana de
    // destino inteira — ficava com duas aulas nessa semana.
    await criarAula('occ_a', quarta(0));
    await httpsCallable(memberFns, 'createBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER,
    });

    await moverAula('occ_a', quarta(1));

    await criarAula('occ_b', new Date(quarta(1).getTime() + 2 * 86_400_000));
    await expect(
      httpsCallable(memberFns, 'createBooking')({
        occurrenceId: 'occ_b',
        memberId: MEMBER,
      }),
    ).rejects.toThrow();
  });

  it('a data guardada na marcação acompanha a aula', async () => {
    // "As minhas marcações" mostra esta cópia e ordena por ela — sem a
    // atualizar, a lista mostrava a hora antiga e podia esconder a aula
    // por a julgar passada.
    await criarAula('occ_a', quarta(0));
    await httpsCallable(memberFns, 'createBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER,
    });

    const novaHora = quarta(1);
    await moverAula('occ_a', novaHora);

    const guardada = (await bookingRef('occ_a').get()).get('startAt') as Timestamp;
    expect(guardada.toDate().getTime()).toBe(novaHora.getTime());
  });

  it('mover dentro da MESMA semana não mexe na utilização', async () => {
    // Trocar as 19:00 pelas 20:00 da mesma quarta não é uma mudança de
    // semana, e não deve haver escrita nenhuma em `usage` — só a data.
    await criarAula('occ_a', quarta(0));
    await httpsCallable(memberFns, 'createBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER,
    });
    const antes = await usagesDoMembro();

    const maisTarde = new Date(quarta(0).getTime() + 3600_000);
    await moverAula('occ_a', maisTarde);

    expect(await usagesDoMembro()).toEqual(antes);
    const guardada = (await bookingRef('occ_a').get()).get('startAt') as Timestamp;
    expect(guardada.toDate().getTime()).toBe(maisTarde.getTime());
  });

  it('uma marcação CANCELADA não é arrastada para a semana nova', async () => {
    // Quem cancelou já teve a utilização devolvida. Mexer-lhe outra vez
    // dava-lhe uma utilização a mais.
    await criarAula('occ_a', quarta(0));
    await httpsCallable(memberFns, 'createBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER,
    });
    await httpsCallable(memberFns, 'cancelBooking')({
      occurrenceId: 'occ_a',
      memberId: MEMBER,
    });
    expect(await usagesDoMembro()).toHaveLength(0);

    await moverAula('occ_a', quarta(1));

    expect(await usagesDoMembro()).toHaveLength(0);
  });
});

describe('a porta antiga ficou fechada', () => {
  it('nem o Gestor consegue mudar a hora por escrita direta', async () => {
    // Sem isto, o caminho antigo continuava a existir ao lado do novo —
    // e é o caminho antigo que deixava a utilização na semana errada.
    // Ver a regra de `sessionOccurrences` em `firestore.rules`.
    await criarAula('occ_a', quarta(0));

    const app = initializeClientApp(
      { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
      'ru-direto',
    );
    clientApps.push(app);
    const auth = getAuth(app);
    connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
    await signInWithCustomToken(
      auth,
      await adminAuth.createCustomToken(MANAGER, {
        tenantId: TENANT_ID,
        roles: ['manager'],
      }),
    );

    const {
      getFirestore: getClientFirestore,
      doc,
      updateDoc,
      connectFirestoreEmulator,
      // O `Timestamp` do SDK CLIENTE. O do Admin é outra classe, e o
      // cliente recusa-o com `invalid-argument` — o teste passava sem a
      // regra ter sido sequer avaliada, que é a pior forma de passar.
      Timestamp: ClientTimestamp,
    } = await import('firebase/firestore');
    const clientDb = getClientFirestore(app);
    connectFirestoreEmulator(clientDb, 'localhost', 8080);

    await expect(
      updateDoc(
        doc(clientDb, `tenants/${TENANT_ID}/sessionOccurrences/occ_a`),
        { startAt: ClientTimestamp.fromDate(quarta(2)) },
      ),
      // E recusado pelas REGRAS, não por outra coisa qualquer.
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });
});
