// UC22 — a troca obrigatória da password temporária, no 1º login.
//
// ## O bug que isto fecha
//
// Reportado em produção, numa conta de INSTRUTOR: entra com a password
// temporária, a app pede a nova, roda, e volta a pedir. Sem fim, sem
// nunca entrar.
//
// O ecrã fazia duas chamadas do cliente — `updatePassword` no Auth, e
// uma escrita direta de `passwordTemporaria: false` no documento. A
// segunda não passa nas Rules: o próprio só pode mexer em `fcmTokens`
// (staff) ou em `phone`/`email`/`updatedAt`/`fcmTokens` (membros).
//
// Logo a password MUDAVA e a flag FICAVA, e o `AuthGate` mandava a
// pessoa de volta ao mesmo ecrã.
//
// Só o Gestor escapava, por ter `allow write` nos dois sítios — e é
// por isso que ninguém deu por ela: quem testa, testa com a conta de
// administração.
//
// Os dois passos passaram para a Cloud Function. Estes testes cobrem
// os três papéis, e o primeiro bloco prova que a escrita direta
// continua (e deve continuar) fechada.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { deleteApp, initializeApp as initializeClientApp, type FirebaseApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import { doc, connectFirestoreEmulator, getFirestore, updateDoc } from 'firebase/firestore';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// O Admin SDK só fala com o emulador de Auth se isto estiver posto, e
// tem de estar ANTES de `initializeApp`. Nenhum teste anterior criava
// utilizadores — usavam todos `createCustomToken`, que é offline — por
// isso a falta nunca tinha dado por si.
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_temp_password';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-temp-password');
const adminFirestore = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);
const tenant = adminFirestore.collection('tenants').doc(TENANT_ID);

const clientApps: FirebaseApp[] = [];

type Sessao = { functions: Functions; app: FirebaseApp };

async function entrar(nome: string, uid: string, roles: string[]): Promise<Sessao> {
  const app = initializeClientApp({ projectId: PROJECT_ID, apiKey: 'demo-key' }, nome);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const functions = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(functions, 'localhost', 5001);
  return { functions, app };
}

/**
 * Cria a conta, mesmo que já exista de uma corrida anterior.
 *
 * O emulador de Auth guarda os utilizadores entre corridas da suite, e
 * um `createUser` com o mesmo uid rebenta com `uid-already-exists` — o
 * teste passava à primeira e falhava a seguir, que é o padrão que o
 * `globalSetup` já trata para os contadores do rate limiter.
 */
async function conta(uid: string): Promise<void> {
  await adminAuth.deleteUser(uid).catch(() => {});
  await adminAuth.createUser({ uid, password: 'Temporaria123' });
}

/** A flag como está no Firestore, agora. */
async function temporaria(coleccao: string, uid: string): Promise<boolean | undefined> {
  const snap = await tenant.collection(coleccao).doc(uid).get();
  return snap.get('passwordTemporaria') as boolean | undefined;
}

beforeAll(async () => {
  await tenant.set({ name: 'Estúdio da password' });

  // Um de cada: é a diferença entre os papéis que esconde o bug.
  await conta('instrutor_tp');
  await tenant.collection('staff').doc('instrutor_tp').set({
    name: 'Instrutor',
    email: 'instrutor@tp.test',
    roles: ['instructor'],
    status: 'active',
    passwordTemporaria: true,
  });

  await conta('aluno_tp');
  await tenant.collection('members').doc('aluno_tp').set({
    memberNumber: '000TP1',
    name: 'Aluno',
    status: 'active',
    passwordTemporaria: true,
  });

  // Instrutor que também treina no estúdio: tem documento nos DOIS, e
  // deixar uma flag para trás repõe o ciclo.
  await conta('ambos_tp');
  await tenant.collection('staff').doc('ambos_tp').set({
    name: 'Instrutor e aluno',
    email: 'ambos@tp.test',
    roles: ['instructor'],
    status: 'active',
    passwordTemporaria: true,
  });
  await tenant.collection('members').doc('ambos_tp').set({
    memberNumber: '000TP2',
    name: 'Instrutor e aluno',
    status: 'active',
    passwordTemporaria: true,
  });
});

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await adminApp.delete();
});

describe('a escrita direta da flag continua fechada', () => {
  it('o Instrutor NÃO consegue limpar a flag por escrita direta', async () => {
    // É esta recusa que partia o ecrã — e está certa. Se deixasse
    // passar, qualquer cliente punha a flag a `false` e saltava a
    // troca obrigatória com a password temporária na mão.
    const { app } = await entrar('tp-direto', 'instrutor_direto', ['instructor']);
    const db = getFirestore(app);
    connectFirestoreEmulator(db, 'localhost', 8080);

    await expect(
      updateDoc(doc(db, `tenants/${TENANT_ID}/staff/instrutor_tp`), {
        passwordTemporaria: false,
      }),
    ).rejects.toThrow(/permission|insufficient/i);
  }, 15_000);
});

describe('completeTemporaryPasswordChange', () => {
  it('o INSTRUTOR troca a password e sai do ciclo', async () => {
    expect(await temporaria('staff', 'instrutor_tp')).toBe(true);

    const { functions } = await entrar('tp-instrutor', 'instrutor_tp', ['instructor']);
    await httpsCallable(functions, 'completeTemporaryPasswordChange')({
      newPassword: 'PasswordNova123',
    });

    expect(await temporaria('staff', 'instrutor_tp')).toBe(false);
  }, 20_000);

  it('o ALUNO também — tinha exatamente o mesmo problema', async () => {
    expect(await temporaria('members', 'aluno_tp')).toBe(true);

    const { functions } = await entrar('tp-aluno', 'aluno_tp', ['member']);
    await httpsCallable(functions, 'completeTemporaryPasswordChange')({
      newPassword: 'PasswordNova123',
    });

    expect(await temporaria('members', 'aluno_tp')).toBe(false);
  }, 20_000);

  it('quem tem documento nos dois sítios fica limpo nos dois', async () => {
    const { functions } = await entrar('tp-ambos', 'ambos_tp', ['instructor', 'member']);
    await httpsCallable(functions, 'completeTemporaryPasswordChange')({
      newPassword: 'PasswordNova123',
    });

    expect(await temporaria('staff', 'ambos_tp')).toBe(false);
    expect(await temporaria('members', 'ambos_tp')).toBe(false);
  }, 20_000);

  it('a password muda MESMO, não é só a flag', async () => {
    // Sem isto, limpar a flag e não mexer na password passava nos
    // testes de cima — e deixava a conta com a temporária para sempre,
    // sem nada a lembrá-la disso.
    const utilizador = await adminAuth.getUser('instrutor_tp');
    expect(utilizador.passwordHash).toBeDefined();

    // A conta PRIMEIRO: entrar com um token personalizado cria o
    // utilizador no emulador, e um `createUser` a seguir rebenta com
    // uid-already-exists.
    await conta('prova_tp');
    await tenant.collection('staff').doc('prova_tp').set({
      name: 'Prova', roles: ['instructor'], status: 'active', passwordTemporaria: true,
    });
    const antes = (await adminAuth.getUser('prova_tp')).passwordHash;

    const { functions } = await entrar('tp-prova', 'prova_tp', ['instructor']);

    await httpsCallable(functions, 'completeTemporaryPasswordChange')({
      newPassword: 'OutraPasswordNova123',
    });

    const depois = (await adminAuth.getUser('prova_tp')).passwordHash;
    expect(depois).not.toBe(antes);
  }, 20_000);

  it('uma password curta é recusada e a flag NÃO é limpa', async () => {
    await conta('curta_tp');
    await tenant.collection('staff').doc('curta_tp').set({
      name: 'Curta', roles: ['instructor'], status: 'active', passwordTemporaria: true,
    });

    const { functions } = await entrar('tp-curta', 'curta_tp', ['instructor']);
    await expect(
      httpsCallable(functions, 'completeTemporaryPasswordChange')({ newPassword: 'abc' }),
    ).rejects.toMatchObject({ code: 'functions/invalid-argument' });

    // A ordem é esta de propósito: flag limpa com password por mudar
    // era pior do que o contrário.
    expect(await temporaria('staff', 'curta_tp')).toBe(true);
  }, 20_000);
});
