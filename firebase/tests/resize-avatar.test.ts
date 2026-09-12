// A foto de perfil, do envio até a app saber que ela existe.
//
// A `resizeAvatar` é um gatilho de Storage: ninguém a chama, ela
// acontece. Isso torna-a fácil de dar por adquirida e difícil de
// confiar — e ela é o que garante que não servimos os 3 MB que saíram
// do telemóvel. Aqui prova-se o encadeamento inteiro contra os
// emuladores: chega uma foto grande, fica um `avatar.jpg` pequeno, o
// original desaparece, e o documento da pessoa ganha o `photoPath` que
// é o sinal para a app deixar de mostrar as iniciais.

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { Jimp } from 'jimp';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_avatar_test';
const MEMBER_ID = 'avatar_member';
const STAFF_ID = 'avatar_staff';
const BUCKET = `${PROJECT_ID}.appspot.com`;

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.STORAGE_EMULATOR_HOST ??= 'http://localhost:9199';

const app = initializeApp(
  { projectId: PROJECT_ID, storageBucket: BUCKET },
  'resize-avatar-test',
);
const firestore = getFirestore(app);
const bucket = getStorage(app).bucket(BUCKET);

const tenantRef = firestore.collection('tenants').doc(TENANT_ID);
const avatarDir = (userId: string) => `tenants/${TENANT_ID}/avatars/${userId}`;

/** O gatilho corre em segundo plano: o upload devolve antes dele. */
async function waitFor<T>(
  read: () => Promise<T | undefined>,
  timeoutMs = 20_000,
): Promise<T | undefined> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await read();
    if (value !== undefined) return value;
    await new Promise((resolve) => setTimeout(resolve, 400));
  }
  return undefined;
}

/**
 * Uma foto "como sai do telemóvel": grande e nada quadrada.
 *
 * Gerada uma vez e reutilizada. Codificar 1600×1200 em JPEG puro
 * JavaScript custa segundos, e este ficheiro corre em paralelo com os
 * outros contra o mesmo emulador — gerá-la quatro vezes tirava tempo de
 * worker a toda a gente e fazia um teste noutro ficheiro estourar o
 * limite de 30 s.
 */
let cachedPhoto: Buffer | undefined;
async function bigPhoto(): Promise<Buffer> {
  cachedPhoto ??= await new Jimp({
    width: 1600,
    height: 1200,
    color: 0x3366ccff,
  }).getBuffer('image/jpeg', { quality: 95 });
  return cachedPhoto;
}

beforeAll(async () => {
  await Promise.all([
    tenantRef.collection('members').doc(MEMBER_ID).set({ name: 'Rita Avatar' }),
    tenantRef.collection('staff').doc(STAFF_ID).set({ name: 'Leo Avatar' }),
  ]);
});

afterAll(async () => {
  await bucket.deleteFiles({ prefix: `tenants/${TENANT_ID}/` }).catch(() => undefined);
  await firestore.recursiveDelete(tenantRef);
});

describe('resizeAvatar', () => {
  it('reduz a foto, apaga o original e marca o documento do aluno', async () => {
    const original = `${avatarDir(MEMBER_ID)}/telemovel.jpg`;
    const source = await bigPhoto();
    await bucket.file(original).save(source, { contentType: 'image/jpeg' });

    const stamped = await waitFor(async () => {
      const doc = await tenantRef.collection('members').doc(MEMBER_ID).get();
      return doc.data()?.photoPath ?? undefined;
    });

    // O `photoPath` é escrito no FIM, só depois de o ficheiro existir:
    // vê-lo aqui significa que a redução terminou.
    expect(stamped).toBe(`${avatarDir(MEMBER_ID)}/avatar.jpg`);

    // E o URL vem já feito. É isto que poupa ao cliente um
    // `getDownloadURL()` por pessoa — cinquenta pedidos de rede numa
    // lista de cinquenta, refeitos a cada entrada no ecrã.
    const doc = await tenantRef.collection('members').doc(MEMBER_ID).get();
    const url = doc.get('photoUrl') as string;
    expect(url).toContain(encodeURIComponent(stamped as string));
    expect(url).toContain('alt=media');

    // O token no URL tem de ser o mesmo que ficou nos metadados do
    // objeto — se divergirem, o URL devolve 403 e todos os avatares
    // aparecem partidos.
    const token = new URL(url).searchParams.get('token');
    const [metadata] = await bucket
      .file(`${avatarDir(MEMBER_ID)}/avatar.jpg`)
      .getMetadata();
    expect(metadata.metadata?.firebaseStorageDownloadTokens).toBe(token);

    const [resized] = await bucket.file(`${avatarDir(MEMBER_ID)}/avatar.jpg`).download();
    const image = await Jimp.read(resized);
    expect(image.width).toBe(160);
    expect(image.height).toBe(160);

    // O ponto todo do exercício: o que fica servido é uma fração do
    // que chegou.
    expect(resized.length).toBeLessThan(source.length / 10);

    // O original não é limpeza pendente — é o que não pode ficar lá.
    const [originalExists] = await bucket.file(original).exists();
    expect(originalExists).toBe(false);
  });

  it('funciona igual para alguém do staff (o caminho não distingue)', async () => {
    await bucket
      .file(`${avatarDir(STAFF_ID)}/foto.jpg`)
      .save(await bigPhoto(), { contentType: 'image/jpeg' });

    const stamped = await waitFor(async () => {
      const doc = await tenantRef.collection('staff').doc(STAFF_ID).get();
      return doc.data()?.photoPath ?? undefined;
    });

    expect(stamped).toBe(`${avatarDir(STAFF_ID)}/avatar.jpg`);
  });

  it('não se dispara a si própria com o `avatar.jpg` que escreve', async () => {
    // Sem a guarda, o ficheiro que a função grava voltava a acordá-la —
    // em ciclo, e a faturação com ele.
    const doc = await tenantRef.collection('members').doc(MEMBER_ID).get();
    const first = doc.data()?.photoUpdatedAt as number;
    expect(first).toBeTypeOf('number');

    await new Promise((resolve) => setTimeout(resolve, 1_500));

    const again = await tenantRef.collection('members').doc(MEMBER_ID).get();
    expect(again.data()?.photoUpdatedAt).toBe(first);
  });

  it('apagar a pessoa antes da foto não deixa a função a rebentar',
    async () => {
      // A ordem real de `deleteMemberData`: apaga os documentos e o
      // avatar. A `clearAvatarOnDelete` acorda a seguir para limpar um
      // `photoPath` num documento que já não existe. Sem tolerar o
      // NOT_FOUND, a função ficava marcada como falhada e a repetir uma
      // escrita que nunca ia ter onde cair. O que se prova aqui é que
      // ela não RECRIA o documento — que é o outro fim errado deste
      // problema, e o que um `set(..., {merge: true})` faria.
      const orfao = 'avatar_orfao';
      await tenantRef.collection('members').doc(orfao).set({ name: 'Fantasma' });
      await bucket
        .file(`${avatarDir(orfao)}/foto.jpg`)
        .save(await bigPhoto(), { contentType: 'image/jpeg' });
      await waitFor(async () => {
        const doc = await tenantRef.collection('members').doc(orfao).get();
        return doc.data()?.photoPath ?? undefined;
      });

      await tenantRef.collection('members').doc(orfao).delete();
      await bucket.file(`${avatarDir(orfao)}/avatar.jpg`).delete();

      // Esperar que a função tenha mesmo corrido, em vez de dormir às
      // cegas: o gatilho de apagamento é o último a mexer neste
      // documento, por isso se ele o fosse recriar já o teria feito.
      await waitFor(async () => {
        const [exists] = await bucket
          .file(`${avatarDir(orfao)}/avatar.jpg`)
          .exists();
        return exists ? undefined : true;
      });
      await new Promise((resolve) => setTimeout(resolve, 1_000));

      const doc = await tenantRef.collection('members').doc(orfao).get();
      expect(doc.exists).toBe(false);
    },
  );

  it('apagar a foto limpa o `photoPath` (senão o avatar ficava partido)',
    async () => {
      await bucket.file(`${avatarDir(MEMBER_ID)}/avatar.jpg`).delete();

      const cleared = await waitFor(async () => {
        const doc = await tenantRef.collection('members').doc(MEMBER_ID).get();
        return doc.data()?.photoPath === undefined ? doc : undefined;
      });

      expect(cleared).toBeDefined();
      // O URL também: deixá-lo para trás dava um avatar partido em vez
      // de voltar às iniciais, que é precisamente o que se queria
      // evitar.
      expect(cleared?.data()?.photoUrl).toBeUndefined();
    },
  );
});
