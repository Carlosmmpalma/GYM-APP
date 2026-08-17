// 🔴 Fase 8 — Storage Rules do vídeo de exercícios (UC15). Primeira
// vez que este projeto testa Storage a sério — até aqui era
// deny-all por omissão (ver storage.rules).
//   1. Leitura ampla dentro do tenant (o Aluno precisa de ver o vídeo
//      dos exercícios do seu plano).
//   2. Escrita só Instrutor OU Gestor.
//   3. "Formato ou tamanho inválido é rejeitado" (mockup) — aplicado a
//      sério aqui, não só na UI: só `contentType` `video/*` é aceite.
//   4. Isolamento entre tenants — o mesmo padrão já coberto para
//      Firestore em `tenant-isolation.test.ts`, aqui para Storage.
//
// Precisa do emulador de Storage a correr. Corre com, a partir da raiz
// do projeto (onde está o firebase.json):
//   firebase emulators:exec --only storage "npm --prefix firebase/tests test"

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';
import { afterAll, beforeAll, describe, it } from 'vitest';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(__dirname, '../../storage.rules');

const TENANT_A = 'tenant_a_real';
const TENANT_B = 'tenant_b_ghost';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-gym-saas-dev-storage-test',
    storage: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

function contextFor(uid: string, tenantId: string, roles: string[]) {
  return testEnv.authenticatedContext(uid, { tenantId, roles });
}

const videoBytes = new Uint8Array([1, 2, 3, 4]);
const videoPath = `tenants/${TENANT_A}/exercises/exercise_1/video`;

describe('Storage Rules — vídeo de exercícios (Fase 8, UC15 fechado)', () => {
  it('um Instrutor CONSEGUE carregar um vídeo (contentType video/*)', async () => {
    const storage = contextFor('instructor_a', TENANT_A, ['instructor']).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, videoPath), videoBytes, { contentType: 'video/mp4' }),
    );
  });

  it('um Gestor CONSEGUE carregar um vídeo', async () => {
    const storage = contextFor('manager_a', TENANT_A, ['manager']).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, videoPath), videoBytes, { contentType: 'video/mp4' }),
    );
  });

  it('um membro NÃO consegue carregar um vídeo', async () => {
    const storage = contextFor('member_a1', TENANT_A, ['member']).storage();
    await assertFails(
      uploadBytes(ref(storage, videoPath), videoBytes, { contentType: 'video/mp4' }),
    );
  });

  it('rejeita um ficheiro que não seja vídeo, mesmo vindo de um Instrutor', async () => {
    const storage = contextFor('instructor_a', TENANT_A, ['instructor']).storage();
    await assertFails(
      uploadBytes(ref(storage, videoPath), videoBytes, { contentType: 'image/png' }),
    );
  });

  it('um membro do tenant CONSEGUE ler o vídeo (precisa de ver o vídeo do seu plano)',
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await uploadBytes(ref(context.storage(), videoPath), videoBytes, {
          contentType: 'video/mp4',
        });
      });

      const storage = contextFor('member_a1', TENANT_A, ['member']).storage();
      await assertSucceeds(getBytes(ref(storage, videoPath)));
    },
  );

  it('um utilizador de OUTRO tenant NÃO consegue ler o vídeo', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(ref(context.storage(), videoPath), videoBytes, {
        contentType: 'video/mp4',
      });
    });

    const storage = contextFor('member_b1', TENANT_B, ['member']).storage();
    await assertFails(getBytes(ref(storage, videoPath)));
  });

  it('um utilizador de OUTRO tenant NÃO consegue carregar vídeo no tenant A', async () => {
    const storage = contextFor('instructor_b', TENANT_B, ['instructor']).storage();
    await assertFails(
      uploadBytes(ref(storage, videoPath), videoBytes, { contentType: 'video/mp4' }),
    );
  });
});
