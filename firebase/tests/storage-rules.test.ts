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
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';
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

const photoBytes = new Uint8Array([1, 2, 3, 4]);
const avatarOf = (tenantId: string, userId: string) =>
  `tenants/${tenantId}/avatars/${userId}/original.jpg`;

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

// Fotos de perfil. A regra é a mesma para aluno e staff — o avatar é a
// mesma coisa nos dois casos — e por isso o que a separa é o dono do
// caminho, não o papel de quem escreve.
describe('Storage Rules — foto de perfil', () => {
  it('a própria pessoa NÃO consegue mudar a sua foto', async () => {
    // Mudou: já foi permitido. A foto de perfil é do estúdio e não da
    // pessoa — é a cara que o instrutor vê na tira da turma para
    // reconhecer quem tem à frente. Um aluno a trocá-la por um desenho
    // qualquer não está a personalizar o perfil dele, está a estragar a
    // ferramenta de outra pessoa.
    const storage = contextFor('member_a1', TENANT_A, ['member']).storage();
    await assertFails(
      uploadBytes(ref(storage, avatarOf(TENANT_A, 'member_a1')), photoBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  it('nem a apagar', async () => {
    const storage = contextFor('member_a1', TENANT_A, ['member']).storage();
    await assertFails(
      deleteObject(ref(storage, avatarOf(TENANT_A, 'member_a1'))),
    );
  });

  it('o Gestor CONSEGUE mudar a foto de um aluno (é ele quem gere as fichas)',
    async () => {
      const storage = contextFor('manager_a', TENANT_A, ['manager']).storage();
      await assertSucceeds(
        uploadBytes(ref(storage, avatarOf(TENANT_A, 'member_a1')), photoBytes, {
          contentType: 'image/jpeg',
        }),
      );
    },
  );

  it('um aluno NÃO consegue mudar a foto de outro aluno', async () => {
    const storage = contextFor('member_a2', TENANT_A, ['member']).storage();
    await assertFails(
      uploadBytes(ref(storage, avatarOf(TENANT_A, 'member_a1')), photoBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  it('um Instrutor NÃO consegue mudar a foto de um aluno', async () => {
    // Deliberado: o instrutor pode carregar vídeos da biblioteca, que
    // são do estúdio, mas a cara de alguém não é conteúdo do estúdio.
    const storage = contextFor('instructor_a', TENANT_A, ['instructor']).storage();
    await assertFails(
      uploadBytes(ref(storage, avatarOf(TENANT_A, 'member_a1')), photoBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  it('rejeita um ficheiro que não seja imagem', async () => {
    const storage = contextFor('member_a1', TENANT_A, ['member']).storage();
    await assertFails(
      uploadBytes(ref(storage, avatarOf(TENANT_A, 'member_a1')), photoBytes, {
        contentType: 'application/pdf',
      }),
    );
  });

  it('alguém de OUTRO tenant não escreve na sua própria pasta dentro do tenant A',
    async () => {
      // O uid é único em toda a instalação: sem o `belongsToTenant`, a
      // regra do "próprio" dava-o por bom em qualquer tenant e a foto
      // passava a ser servida no tenant A.
      const storage = contextFor('member_a1', TENANT_B, ['member']).storage();
      await assertFails(
        uploadBytes(ref(storage, avatarOf(TENANT_A, 'member_a1')), photoBytes, {
          contentType: 'image/jpeg',
        }),
      );
    },
  );

  it('um membro do tenant CONSEGUE ler o avatar de outro (aparece nas listas)',
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await uploadBytes(
          ref(context.storage(), avatarOf(TENANT_A, 'member_a1')),
          photoBytes,
          { contentType: 'image/jpeg' },
        );
      });

      const storage = contextFor('member_a2', TENANT_A, ['member']).storage();
      await assertSucceeds(getBytes(ref(storage, avatarOf(TENANT_A, 'member_a1'))));
    },
  );

  it('um utilizador de OUTRO tenant NÃO consegue ler o avatar', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(
        ref(context.storage(), avatarOf(TENANT_A, 'member_a1')),
        photoBytes,
        { contentType: 'image/jpeg' },
      );
    });

    const storage = contextFor('member_b1', TENANT_B, ['member']).storage();
    await assertFails(getBytes(ref(storage, avatarOf(TENANT_A, 'member_a1'))));
  });
});
