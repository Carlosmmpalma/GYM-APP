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
