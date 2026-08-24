// Reportado a testar: "ao criar contas, se não colocar alguns dados
// aparece um erro firebase internal".
//
// Duas causas distintas, as duas confirmadas contra o emulador:
//
//  1. Metade das funções fazia `schema.parse(...)`, que lança um
//     `ZodError` cru. Uma exceção que não é `HttpsError` chega ao
//     cliente como **`internal` / `INTERNAL`** — "erro interno" para
//     quem só se esqueceu de preencher um campo. A outra metade
//     devolvia `parsed.error.message`, que é o JSON do erro do zod
//     despejado no ecrã.
//  2. Criar staff com um email já usado nem sequer passava pela
//     validação: `auth.createUser` rebentava com
//     `auth/email-already-exists` e ninguém apanhava — outra vez
//     `internal`.
//
// O que estes testes fixam é o CONTRATO com a app: código certo e
// mensagem que uma pessoa consegue ler.

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
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_input_errors';
// Um gestor novo por corrida: as funções de criação de contas têm
// limite de chamadas por utilizador (20 em 5 minutos), e o contador
// sobrevive entre corridas no emulador. Sem isto, a segunda vez que se
// corre o ficheiro falha com `resource-exhausted` — que não é o que
// estes testes andam a provar.
const MANAGER = `input_gestor_${Date.now()}`;
const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-input');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let fns: Functions;

/** O erro tal como a app o recebe. */
async function callAndCatch(
  name: string,
  payload: unknown,
): Promise<{ code: string; message: string }> {
  try {
    await httpsCallable(fns, name)(payload);
    throw new Error(`${name} devia ter falhado e não falhou`);
  } catch (error) {
    const e = error as { code?: string; message?: string };
    return { code: e.code ?? '', message: e.message ?? '' };
  }
}

/** A mesma régua que a app usa para decidir se mostra a mensagem. */
function isReadable(message: string): boolean {
  const trimmed = message.trim();
  return (
    trimmed.length > 0 &&
    trimmed.length <= 300 &&
    !trimmed.startsWith('[') &&
    !trimmed.startsWith('{') &&
    trimmed.toUpperCase() !== trimmed
  );
}

beforeAll(async () => {
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });
  await adminAuth
    .createUser({
      uid: MANAGER,
      email: `${MANAGER}@example.test`,
      password: 'TestPass123!',
    })
    .catch(() => undefined);

  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    'input-errors',
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
  fns = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(fns, 'localhost', 5001);
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

describe('Campos em falta', () => {
  it('criar aluno sem nome diz QUE campo falta', async () => {
    const error = await callAndCatch('createMember', { name: '' });

    expect(error.code).toBe('functions/invalid-argument');
    expect(error.message).toContain('nome');
    expect(isReadable(error.message)).toBe(true);
  }, 30_000);

  it('criar aluno sem nada não devolve "internal"', async () => {
    const error = await callAndCatch('createMember', {});

    // O sintoma reportado: `internal`/`INTERNAL`, que não diz nada a
    // ninguém e sugere que a app se partiu.
    expect(error.code).not.toBe('functions/internal');
    expect(error.message).not.toContain('INTERNAL');
  }, 30_000);

  it('criar staff sem email diz que falta o email', async () => {
    const error = await callAndCatch('createStaff', {
      name: 'Teste',
      email: '',
      roles: ['instructor'],
    });

    expect(error.code).toBe('functions/invalid-argument');
    expect(error.message.toLowerCase()).toContain('email');
    expect(isReadable(error.message)).toBe(true);
  }, 30_000);

  it('criar staff sem papéis explica que é preciso escolher um',
    async () => {
      const error = await callAndCatch('createStaff', {
        name: 'Teste',
        email: 'sem-papeis@example.test',
        roles: [],
      });

      expect(error.code).toBe('functions/invalid-argument');
      expect(error.message.toLowerCase()).toContain('papéis');
    }, 30_000);

  it('uma data malformada diz qual é e que formato usar', async () => {
    const error = await callAndCatch('createMember', {
      name: 'Teste',
      birthDate: 'ontem',
    });

    expect(error.code).toBe('functions/invalid-argument');
    expect(error.message).toContain('birthDate');
  }, 30_000);

  it('as funções que usavam `parse` também traduzem', async () => {
    // `waitlist` era uma das dez que lançava `ZodError` cru.
    const error = await callAndCatch('joinWaitlist', {});

    expect(error.code).not.toBe('functions/internal');
    expect(isReadable(error.message)).toBe(true);
  }, 30_000);
});

describe('Email já usado', () => {
  it('dá "já existe" com uma frase que se percebe, não "internal"',
    async () => {
      const email = `repetido_${Date.now()}@example.test`;
      await httpsCallable(fns, 'createStaff')({
        name: 'Primeiro',
        email,
        roles: ['instructor'],
      });

      const error = await callAndCatch('createStaff', {
        name: 'Segundo',
        email,
        roles: ['instructor'],
      });

      // Era exatamente aqui que aparecia `internal`.
      expect(error.code).toBe('functions/already-exists');
      expect(error.message.toLowerCase()).toContain('já existe');
      expect(isReadable(error.message)).toBe(true);
    }, 60_000);
});
