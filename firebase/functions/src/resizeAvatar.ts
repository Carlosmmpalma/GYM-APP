import { randomUUID } from 'node:crypto';

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onObjectDeleted, onObjectFinalized } from 'firebase-functions/v2/storage';

/// O lado do tamanho final, em píxeis.
///
/// O avatar maior da app tem 34pt; a 3x de densidade são ~100px. 160
/// dá folga para ecrãs densos sem servir nada que não se veja.
const SIZE = 160;

/**
 * O URL público de um objeto do Storage, dado o token dos metadados.
 *
 * É a mesma forma que o `getDownloadURL()` do SDK devolve — o caminho
 * tem de ir com as barras codificadas, que é o que distingue este
 * `encodeURIComponent` de um `encodeURI`.
 */
function downloadUrl(bucket: string, path: string, token: string): string {
  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${token}`
  );
}

/**
 * Escreve num documento que pode já não existir.
 *
 * O caso real é apagar um membro: a `deleteMemberData` apaga os
 * documentos e o avatar, e a `clearAvatarOnDelete` acorda a seguir para
 * limpar um `photoPath` de um documento que já foi. Entre o `get` e o
 * `update` cabe a corrida, e o `update` rebenta com NOT_FOUND — o que
 * marca a função como falhada e a põe a repetir uma escrita que nunca
 * vai ter onde cair.
 *
 * Não é um erro: é a ordem normal das coisas quando alguém é apagado.
 */
async function updateIfExists(
  ref: FirebaseFirestore.DocumentReference,
  data: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>,
): Promise<void> {
  try {
    await ref.update(data);
  } catch (error) {
    if ((error as { code?: number }).code === 5) return; // NOT_FOUND
    throw error;
  }
}

/**
 * Reduz a foto de perfil assim que ela chega, e deita fora o original.
 *
 * ## Porque é que isto existe
 *
 * O avatar aparece em LISTAS — em Gestão › Utilizadores são cinquenta
 * pessoas de uma vez. Uma foto como sai do telemóvel tem ~3 MB:
 *
 *   · 50 fotos por abertura do ecrã  →  ~150 MB
 *   · nível gratuito do Storage       →  1 GB/dia
 *
 * Sete aberturas desse ecrã esgotavam o dia. Reduzida a 160px (~8 KB),
 * a mesma lista são ~400 KB — e o browser guarda-as em cache.
 *
 * ## Porque no servidor
 *
 * Podia ser feito no cliente antes de enviar, e sairia mais barato (uma
 * invocação a menos e nenhum original a subir). Foi decisão do produto
 * mantê-lo do nosso lado: o cliente envia a foto tal como a tem, e a
 * garantia de que nada grande chega a ser servido não depende de a app
 * estar atualizada. A largura de banda de ENTRADA no Storage não é
 * faturada, por isso o custo do original é o instante em que existe.
 *
 * ## O original é apagado
 *
 * Não é limpeza: é o que garante que ninguém o serve por engano. Só o
 * `avatar.jpg` fica, e é esse que a app conhece.
 *
 * ## E escreve o URL, não só o caminho
 *
 * Um caminho não se mostra: para o transformar em imagem o cliente
 * tinha de chamar `getDownloadURL()`, que é um pedido de rede por
 * pessoa. Numa lista de cinquenta são cinquenta pedidos — e outra vez
 * cinquenta ao reentrar no ecrã, porque o resultado não fica em lado
 * nenhum. A lista abria com cinquenta círculos de iniciais e as fotos
 * iam caindo à medida que os pedidos voltavam.
 *
 * O URL de download do Firebase é só o caminho mais um token guardado
 * nos metadados do objeto. Se for ESTA função a gerar o token, o URL
 * é construível aqui e viaja com o documento da pessoa, que a app já
 * lê de qualquer maneira. Cinquenta pedidos passam a zero, e as fotos
 * aparecem com a lista em vez de depois dela.
 *
 * Não muda quem consegue ver o quê: o `getDownloadURL()` que isto
 * substitui já devolvia exatamente este URL. Muda só de onde vem —
 * e vem para as mesmas pessoas, que são as que conseguem ler o
 * documento.
 *
 * Um token novo a cada envio é também o que trata da cache: o URL
 * muda, por isso a foto nova aparece já, apesar do ano de validade.
 */
export const resizeAvatar = onObjectFinalized(
  { memory: '512MiB' },
  async (event) => {
    const filePath = event.data.name;
    if (!filePath) return;

    // `tenants/{tenantId}/avatars/{userId}/original...`
    const match = filePath.match(/^tenants\/([^/]+)\/avatars\/([^/]+)\/(.+)$/);
    if (!match) return;

    const [, tenantId, userId, fileName] = match;

    // A própria função escreve `avatar.jpg` nesta pasta; sem esta
    // guarda, a escrita voltava a disparar o gatilho — em ciclo.
    if (fileName === 'avatar.jpg') return;

    const bucket = getStorage().bucket(event.data.bucket);
    const original = bucket.file(filePath);

    try {
      // `import` aqui dentro, e não no topo do ficheiro.
      //
      // O `index.ts` importa TUDO, por isso qualquer função carrega o
      // módulo de todas as outras no arranque a frio. Medido: o
      // `index.js` inteiro leva ~620 ms a carregar, e ~100 ms deles são
      // o jimp — que só esta função usa. Uma marcação pagava-o de cada
      // vez que a instância era nova.
      //
      // Compilado para CommonJS isto vira um `require()` adiado, o que é
      // exatamente o que se quer: o custo passa a ser de quem envia uma
      // foto.
      const { Jimp } = await import('jimp');

      const [buffer] = await original.download();
      const image = await Jimp.read(buffer);

      // `cover` e não `resize`: corta ao centro para dar um quadrado,
      // em vez de espremer a pessoa para caber num círculo.
      image.cover({ w: SIZE, h: SIZE });
      const resized = await image.getBuffer('image/jpeg', { quality: 80 });

      const path = `tenants/${tenantId}/avatars/${userId}/avatar.jpg`;
      const target = bucket.file(path);

      // O token que torna o URL de download construível — ver a nota
      // acima. É o mesmo campo de metadados que o `getDownloadURL()`
      // do cliente iria buscar; a diferença é que aqui já sabemos qual
      // é, em vez de haver um pedido por pessoa para o descobrir.
      const token = randomUUID();
      await target.save(resized, {
        contentType: 'image/jpeg',
        metadata: {
          // Um ano. O caminho é fixo por pessoa, mas o token muda a
          // cada envio e com ele o URL, por isso uma foto nova aparece
          // logo em vez de esperar que a cache expire.
          cacheControl: 'public, max-age=31536000',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });

      // Só agora é que a app fica a saber que há foto. Escrever isto
      // antes do ficheiro existir dava um avatar partido no intervalo.
      const firestore = getFirestore();
      const tenantRef = firestore.collection('tenants').doc(tenantId);
      const stamp = {
        photoPath: path,
        photoUrl: downloadUrl(event.data.bucket, path, token),
        photoUpdatedAt: Date.now(),
      };

      // Pode ser um aluno ou alguém do staff — o caminho não distingue,
      // e não vale a pena inventar dois sítios para a mesma coisa.
      const [member, staff] = await Promise.all([
        tenantRef.collection('members').doc(userId).get(),
        tenantRef.collection('staff').doc(userId).get(),
      ]);
      if (member.exists) await updateIfExists(member.ref, stamp);
      if (staff.exists) await updateIfExists(staff.ref, stamp);
    } finally {
      // Mesmo que a redução falhe: um original de 3 MB neste caminho é
      // exatamente o que isto existe para evitar que fique servido.
      await original.delete().catch(() => undefined);
    }
  },
);

/**
 * Limpa o `photoPath` quando alguém remove a foto.
 *
 * O simétrico da `resizeAvatar`, e pelo mesmo motivo de ser o servidor
 * a fazê-lo: um aluno não pode escrever no seu próprio documento (as
 * Security Rules limitam os campos a que ele toca), por isso deixar
 * esta escrita ao cliente obrigaria a abrir a regra só para isto.
 *
 * Sem ela, remover a foto apagava o ficheiro e deixava o documento a
 * apontar para ele — a app pedia um URL que já não existe e o avatar
 * ficava partido em vez de voltar às iniciais.
 */
export const clearAvatarOnDelete = onObjectDeleted(async (event) => {
  const filePath = event.data.name;
  if (!filePath) return;

  const match = filePath.match(/^tenants\/([^/]+)\/avatars\/([^/]+)\/avatar\.jpg$/);
  if (!match) return;

  const [, tenantId, userId] = match;
  const tenantRef = getFirestore().collection('tenants').doc(tenantId);
  const cleared = {
    photoPath: FieldValue.delete(),
    photoUrl: FieldValue.delete(),
    photoUpdatedAt: FieldValue.delete(),
  };

  for (const collection of ['members', 'staff'] as const) {
    await updateIfExists(tenantRef.collection(collection).doc(userId), cleared);
  }
});
