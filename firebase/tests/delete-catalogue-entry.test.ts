// Eliminar serviços, planos e modalidades — e, sobretudo, RECUSAR
// quando alguma coisa depende deles.
//
// A regra do domínio sempre foi "nunca eliminar, só desativar", pela
// melhor das razões: um plano eliminado deixa o histórico financeiro do
// membro a mostrar ids em vez de "Aulas de Grupo — 44,90 €". Mas a
// regra estava a ser aplicada também ao caso banal — criar um serviço
// com o nome errado e ficar com ele para sempre — e a única saída era
// pedir a um programador.
//
// O que interessa testar aqui é a fronteira entre os dois casos.
//
// Precisa dos emuladores Firestore + Functions + Auth e de
// `firebase/functions` compilado. Ver `booking-concurrency.test.ts`.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
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
const TENANT_ID = 'tenant_delete_catalogue';
const MANAGER_ID = 'delcat_manager';
const INSTRUCTOR_ID = 'delcat_instructor';
const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-delcat-test');
const adminAuth = getAdminAuth(adminApp);
const db = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFunctions: Functions;
let instructorFunctions: Functions;

async function signedInFunctions(
  appName: string,
  uid: string,
  claims: { tenantId: string; roles: string[] },
): Promise<Functions> {
  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-api-key' }, appName);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(auth, await adminAuth.createCustomToken(uid, claims));
  const functions = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return functions;
}

function del(functions: Functions, kind: string, id: string) {
  return httpsCallable(functions, 'deleteCatalogueEntry')({ kind, id });
}

beforeAll(async () => {
  await db.recursiveDelete(db.doc(`tenants/${TENANT_ID}`));
  await db.doc(`tenants/${TENANT_ID}`).set({ name: 'Ginásio do teste' });

  for (const [uid, roles] of [
    [MANAGER_ID, ['manager']],
    [INSTRUCTOR_ID, ['instructor']],
  ] as const) {
    await db.doc(`tenants/${TENANT_ID}/staff/${uid}`).set({
      name: uid,
      email: `${uid}@example.test`,
      roles: [...roles],
      status: 'active',
    });
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }

  managerFunctions = await signedInFunctions('delcat-manager', MANAGER_ID, {
    tenantId: TENANT_ID,
    roles: ['manager'],
  });
  instructorFunctions = await signedInFunctions('delcat-instructor', INSTRUCTOR_ID, {
    tenantId: TENANT_ID,
    roles: ['instructor'],
  });
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

beforeEach(async () => {
  // Cada teste monta as suas referências; herdar as do anterior tornava
  // os resultados dependentes da ordem de execução.
  for (const collection of [
    'services',
    'plans',
    'modalities',
    'subscriptions',
    'sessionSeries',
    'sessionOccurrences',
    'exercises',
    'exerciseCategories',
    'freeTrainingSchedules',
    'members',
  ]) {
    const snap = await db.collection(`tenants/${TENANT_ID}/${collection}`).get();
    await Promise.all(snap.docs.map((doc) => db.recursiveDelete(doc.ref)));
  }
  await db.doc(`tenants/${TENANT_ID}/config/bookingPolicy`).set({}, { merge: false });
  await db.doc(`tenants/${TENANT_ID}/staff/${MANAGER_ID}`).set(
    { serviceIds: [], modalityIds: [] },
    { merge: true },
  );
});

describe('deleteCatalogueEntry', () => {
  it('elimina um serviço que ninguém usa', async () => {
    await db.doc(`tenants/${TENANT_ID}/services/svc_orfao`).set({
      name: 'Serviço criado por engano',
      active: false,
    });

    await del(managerFunctions, 'service', 'svc_orfao');

    const after = await db.doc(`tenants/${TENANT_ID}/services/svc_orfao`).get();
    expect(after.exists).toBe(false);
  });

  it('recusa um serviço com aulas, e diz quantas', async () => {
    await db.doc(`tenants/${TENANT_ID}/services/svc_usado`).set({
      name: 'Aulas de grupo',
      active: true,
    });
    await db.doc(`tenants/${TENANT_ID}/sessionSeries/serie_1`).set({
      serviceId: 'svc_usado',
      dayOfWeek: 1,
      startTime: '18:00',
      durationMinutes: 60,
      capacity: 6,
      status: 'active',
    });

    await expect(del(managerFunctions, 'service', 'svc_usado')).rejects.toMatchObject({
      code: 'functions/failed-precondition',
    });

    // A recusa não serve de nada sem dizer o quê — é a diferença entre
    // o Gestor resolver sozinho e telefonar a alguém.
    try {
      await del(managerFunctions, 'service', 'svc_usado');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 série(s) de aulas');
    }

    const after = await db.doc(`tenants/${TENANT_ID}/services/svc_usado`).get();
    expect(after.exists).toBe(true);
  });

  it('recusa um serviço que é o de treino livre configurado', async () => {
    // Este não aparece em query nenhuma — vive num campo de
    // configuração. Sem esta verificação, eliminá-lo deixava o treino
    // livre a apontar para o vazio.
    await db.doc(`tenants/${TENANT_ID}/services/svc_livre`).set({
      name: 'Treino livre',
      active: true,
    });
    await db
      .doc(`tenants/${TENANT_ID}/config/bookingPolicy`)
      .set({ freeTrainingServiceId: 'svc_livre' }, { merge: true });

    try {
      await del(managerFunctions, 'service', 'svc_livre');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('a definição de serviço de treino livre');
    }
  });

  it('recusa um serviço incluído num plano', async () => {
    await db.doc(`tenants/${TENANT_ID}/services/svc_no_plano`).set({
      name: 'Hyrox',
      active: true,
    });
    await db.doc(`tenants/${TENANT_ID}/plans/plan_x`).set({
      name: 'Plano X',
      currentPrice: 30,
      currency: 'EUR',
      active: true,
    });
    await db.doc(`tenants/${TENANT_ID}/plans/plan_x/services/svc_no_plano`).set({
      serviceId: 'svc_no_plano',
      enabled: true,
      usage: { type: 'unlimited' },
    });

    try {
      await del(managerFunctions, 'service', 'svc_no_plano');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 plano(s) que o incluem');
    }
  });

  it('elimina um plano sem subscrições, incluindo a subcoleção de serviços', async () => {
    await db.doc(`tenants/${TENANT_ID}/plans/plan_vazio`).set({
      name: 'Plano duplicado',
      currentPrice: 40,
      currency: 'EUR',
      active: true,
    });
    await db.doc(`tenants/${TENANT_ID}/plans/plan_vazio/services/svc_a`).set({
      serviceId: 'svc_a',
      enabled: true,
      usage: { type: 'unlimited' },
    });

    await del(managerFunctions, 'plan', 'plan_vazio');

    expect((await db.doc(`tenants/${TENANT_ID}/plans/plan_vazio`).get()).exists).toBe(false);
    // A subcoleção sobrevive a apagar só o pai — ficaria invisível na
    // consola e renascia se alguém recriasse o plano com o mesmo id.
    const orphans = await db.collection(`tenants/${TENANT_ID}/plans/plan_vazio/services`).get();
    expect(orphans.empty).toBe(true);
  });

  it('recusa um plano com subscrições, mesmo canceladas', async () => {
    // Cancelada continua a ser histórico financeiro do membro: é
    // precisamente o registo que precisa do nome e do preço do plano.
    await db.doc(`tenants/${TENANT_ID}/plans/plan_com_historico`).set({
      name: 'Aulas de Grupo',
      currentPrice: 44.9,
      currency: 'EUR',
      active: true,
    });
    await db.doc(`tenants/${TENANT_ID}/subscriptions/sub_1`).set({
      memberId: 'qualquer',
      planId: 'plan_com_historico',
      status: 'cancelled',
      activeServiceIds: [],
    });

    try {
      await del(managerFunctions, 'plan', 'plan_com_historico');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 subscrição(ões) de membros');
    }
  });

  it('elimina uma modalidade que nenhuma aula usa', async () => {
    await db.doc(`tenants/${TENANT_ID}/modalities/mod_orfa`).set({
      name: 'Modalidade a mais',
      active: true,
      serviceIds: [],
    });

    await del(managerFunctions, 'modality', 'mod_orfa');

    expect((await db.doc(`tenants/${TENANT_ID}/modalities/mod_orfa`).get()).exists).toBe(false);
  });

  it('recusa uma modalidade atribuída a um instrutor', async () => {
    await db.doc(`tenants/${TENANT_ID}/modalities/mod_usada`).set({
      name: 'Pilates',
      active: true,
      serviceIds: [],
    });
    await db
      .doc(`tenants/${TENANT_ID}/staff/${MANAGER_ID}`)
      .set({ modalityIds: ['mod_usada'] }, { merge: true });

    try {
      await del(managerFunctions, 'modality', 'mod_usada');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 instrutor(es) com esta modalidade atribuída');
    }
  });

  it('elimina um exercício que ninguém tem prescrito', async () => {
    await db.doc(`tenants/${TENANT_ID}/exercises/ex_livre`).set({
      name: 'Exercício a mais',
      description: '',
      muscleGroup: 'Core',
    });

    await del(managerFunctions, 'exercise', 'ex_livre');

    expect((await db.doc(`tenants/${TENANT_ID}/exercises/ex_livre`).get()).exists).toBe(false);
  });

  it('recusa um exercício prescrito no plano de um aluno', async () => {
    await db.doc(`tenants/${TENANT_ID}/exercises/ex_usado`).set({
      name: 'Agachamento',
      description: '',
      muscleGroup: 'Pernas',
    });
    await db.doc(`tenants/${TENANT_ID}/members/aluno_x`).set({
      name: 'Aluno X',
      memberNumber: '000900',
      status: 'active',
    });
    await db.doc(`tenants/${TENANT_ID}/members/aluno_x/planEntries/entry_1`).set({
      exerciseId: 'ex_usado',
      sets: 3,
      reps: '10',
    });

    try {
      await del(managerFunctions, 'exercise', 'ex_usado');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 prescrição(ões) em planos de alunos');
    }
  });

  it('a biblioteca de exercícios também é do instrutor', async () => {
    // Instrutores já criam e editam exercícios (`firestore.rules`);
    // poderem eliminar da mesma é coerente. Tudo o resto continua
    // exclusivo do Gestor — ver o teste do serviço mais abaixo.
    await db.doc(`tenants/${TENANT_ID}/exercises/ex_do_instrutor`).set({
      name: 'Criado pelo instrutor',
      description: '',
      muscleGroup: 'Peito',
    });

    await del(instructorFunctions, 'exercise', 'ex_do_instrutor');

    expect(
      (await db.doc(`tenants/${TENANT_ID}/exercises/ex_do_instrutor`).get()).exists,
    ).toBe(false);
  });

  it('recusa uma série que já gerou aulas', async () => {
    await db.doc(`tenants/${TENANT_ID}/sessionSeries/serie_com_aulas`).set({
      serviceId: 'qualquer',
      dayOfWeek: 1,
      startTime: '18:00',
      durationMinutes: 60,
      capacity: 6,
      status: 'active',
    });
    await db.doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_1`).set({
      seriesId: 'serie_com_aulas',
      serviceId: 'qualquer',
      status: 'scheduled',
      capacity: 6,
      activeBookingCount: 0,
    });

    try {
      await del(managerFunctions, 'series', 'serie_com_aulas');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 aula(s) já geradas por esta série');
    }
  });

  it('elimina staff sem aulas, e a conta de autenticação com ele', async () => {
    const uid = 'delcat_staff_orfao';
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
    await db.doc(`tenants/${TENANT_ID}/staff/${uid}`).set({
      name: 'Instrutor criado por engano',
      email: `${uid}@example.test`,
      roles: ['instructor'],
      status: 'active',
    });
    await db
      .doc(`tenants/${TENANT_ID}/staff/${uid}/private/profile`)
      .set({ phone: '910000000' });

    await del(managerFunctions, 'staff', uid);

    expect((await db.doc(`tenants/${TENANT_ID}/staff/${uid}`).get()).exists).toBe(false);
    // Os dados pessoais vivem numa subcoleção: apagar só o pai
    // deixava-a órfã e legível por quem soubesse o caminho.
    const priv = await db.collection(`tenants/${TENANT_ID}/staff/${uid}/private`).get();
    expect(priv.empty).toBe(true);
    // E a conta deixa de conseguir autenticar-se.
    await expect(adminAuth.getUser(uid)).rejects.toThrow();
  });

  it('um Gestor não se elimina a si próprio', async () => {
    // Ficaria trancado fora, a precisar exatamente do programador que
    // isto existe para dispensar.
    await expect(del(managerFunctions, 'staff', MANAGER_ID)).rejects.toMatchObject({
      code: 'functions/failed-precondition',
    });
    expect((await db.doc(`tenants/${TENANT_ID}/staff/${MANAGER_ID}`).get()).exists).toBe(true);
  });

  it('elimina uma aula avulsa vazia E as subcoleções dela', async () => {
    // `activeBookingCount == 0` NÃO quer dizer "sem marcações":
    // cancelar põe `status: 'cancelled'` e deixa o documento. Apagar só
    // o pai deixava-o órfão — e como as aulas de série têm id
    // determinístico, voltava a aparecer agarrado à aula recriada.
    await db.doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_avulsa`).set({
      serviceId: 'svc',
      seriesId: null,
      status: 'scheduled',
      capacity: 6,
      activeBookingCount: 0,
    });
    await db
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_avulsa/bookings/aluno_1`)
      .set({ memberId: 'aluno_1', status: 'cancelled' });
    await db
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_avulsa/waitlist/aluno_2`)
      .set({ memberId: 'aluno_2', position: 1 });

    await del(managerFunctions, 'occurrence', 'occ_avulsa');

    expect(
      (await db.doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_avulsa`).get()).exists,
    ).toBe(false);
    const bookings = await db
      .collection(`tenants/${TENANT_ID}/sessionOccurrences/occ_avulsa/bookings`)
      .get();
    const waitlist = await db
      .collection(`tenants/${TENANT_ID}/sessionOccurrences/occ_avulsa/waitlist`)
      .get();
    expect(bookings.empty).toBe(true);
    expect(waitlist.empty).toBe(true);
  });

  it('recusa uma aula com alunos inscritos', async () => {
    await db.doc(`tenants/${TENANT_ID}/sessionOccurrences/occ_cheia`).set({
      serviceId: 'svc',
      seriesId: null,
      status: 'scheduled',
      capacity: 6,
      activeBookingCount: 2,
    });

    try {
      await del(managerFunctions, 'occurrence', 'occ_cheia');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('2 aluno(s) inscritos');
    }
  });

  it('recusa uma aula gerada por série, mesmo vazia', async () => {
    // O id é determinístico (`{seriesId}_{data}`) e o cron da noite
    // recria-a. Apagar era trabalho que se desfaz sozinho.
    await db
      .doc(`tenants/${TENANT_ID}/sessionOccurrences/serie_x_2026-09-01`)
      .set({
        serviceId: 'svc',
        seriesId: 'serie_x',
        status: 'scheduled',
        capacity: 6,
        activeBookingCount: 0,
      });

    try {
      await del(managerFunctions, 'occurrence', 'serie_x_2026-09-01');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain(
        'a série que a gera (voltaria a ser criada esta noite)',
      );
    }
  });

  it('elimina uma categoria de exercícios que ninguém usa', async () => {
    await db.doc(`tenants/${TENANT_ID}/exerciseCategories/cat_orfa`).set({
      name: 'Categoria a mais',
      active: true,
    });

    await del(managerFunctions, 'exerciseCategory', 'cat_orfa');

    expect(
      (await db.doc(`tenants/${TENANT_ID}/exerciseCategories/cat_orfa`).get()).exists,
    ).toBe(false);
  });

  it('recusa uma categoria com exercícios, contando pelo NOME', async () => {
    // Os exercícios guardam o texto da categoria, não o id — para não
    // custarem uma leitura extra nos ecrãs do aluno. A contagem tem de
    // seguir a mesma regra.
    await db.doc(`tenants/${TENANT_ID}/exerciseCategories/cat_pernas`).set({
      name: 'Pernas',
      active: true,
    });
    await db.doc(`tenants/${TENANT_ID}/exercises/ex_agachamento`).set({
      name: 'Agachamento',
      description: '',
      category: 'Pernas',
    });

    try {
      await del(managerFunctions, 'exerciseCategory', 'cat_pernas');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 exercício(s) nesta categoria');
    }
  });

  it('o Instrutor também gere as categorias', async () => {
    // Quem cria exercícios é quem precisa de os arrumar. Obrigar a
    // pedir ao Gestor recriava o bloqueio que isto veio resolver.
    await db.doc(`tenants/${TENANT_ID}/exerciseCategories/cat_do_instrutor`).set({
      name: 'Criada pelo instrutor',
      active: true,
    });

    await del(instructorFunctions, 'exerciseCategory', 'cat_do_instrutor');

    expect(
      (await db.doc(`tenants/${TENANT_ID}/exerciseCategories/cat_do_instrutor`).get())
        .exists,
    ).toBe(false);
  });

  it('elimina a grelha de uma semana, com blocos e marcações', async () => {
    // A primeira versão disto era escrita direta do cliente e NUNCA
    // funcionou: `freeTrainingSchedules` é `write: false` nas Rules, o
    // batch falhava no documento-pai e não apagava nada.
    const week = `tenants/${TENANT_ID}/freeTrainingSchedules/2026-08-24`;
    await db.doc(week).set({ status: 'published' });
    await db.doc(`${week}/slots/slot_1`).set({
      serviceId: 'svc',
      capacity: 10,
      activeBookingCount: 0,
    });
    // Marcação cancelada: `activeBookingCount` é 0 mas o documento
    // fica. Apagar só o pai deixava-o órfão — e o id da semana é
    // determinístico, por isso voltava a aparecer se a semana fosse
    // gerada outra vez.
    await db
      .doc(`${week}/slots/slot_1/bookings/aluno_1`)
      .set({ memberId: 'aluno_1', status: 'cancelled' });

    await del(managerFunctions, 'freeTrainingWeek', '2026-08-24');

    expect((await db.doc(week).get()).exists).toBe(false);
    const slots = await db.collection(`${week}/slots`).get();
    const bookings = await db.collection(`${week}/slots/slot_1/bookings`).get();
    expect(slots.empty).toBe(true);
    expect(bookings.empty).toBe(true);
  });

  it('recusa uma semana com blocos ocupados', async () => {
    const week = `tenants/${TENANT_ID}/freeTrainingSchedules/2026-09-07`;
    await db.doc(week).set({ status: 'published' });
    await db.doc(`${week}/slots/slot_cheio`).set({
      serviceId: 'svc',
      capacity: 10,
      activeBookingCount: 2,
    });
    await db.doc(`${week}/slots/slot_vazio`).set({
      serviceId: 'svc',
      capacity: 10,
      activeBookingCount: 0,
    });

    try {
      await del(managerFunctions, 'freeTrainingWeek', '2026-09-07');
      expect.unreachable('devia ter recusado');
    } catch (error) {
      const details = (error as { details?: { blockers?: string[] } }).details;
      expect(details?.blockers).toContain('1 bloco(s) com alunos inscritos');
    }

    // E nada foi apagado — nem o bloco vazio.
    expect((await db.collection(`${week}/slots`).get()).size).toBe(2);
  });

  it('um instrutor não pode eliminar nada', async () => {
    await db.doc(`tenants/${TENANT_ID}/services/svc_protegido`).set({
      name: 'Serviço',
      active: true,
    });

    await expect(del(instructorFunctions, 'service', 'svc_protegido')).rejects.toMatchObject({
      code: 'functions/permission-denied',
    });

    expect((await db.doc(`tenants/${TENANT_ID}/services/svc_protegido`).get()).exists).toBe(true);
  });

  it('recusa um tipo desconhecido em vez de rebentar', async () => {
    await expect(del(managerFunctions, 'ginasio', 'seja-o-que-for')).rejects.toMatchObject({
      code: 'functions/invalid-argument',
    });
  });

  it('diz que não existe quando já foi eliminado', async () => {
    await expect(del(managerFunctions, 'service', 'nunca_existiu')).rejects.toMatchObject({
      code: 'functions/not-found',
    });
  });
});
