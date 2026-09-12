// Configura o CORS do bucket do Storage.
//
// ## O bug que isto corrige
//
// As fotos de perfil eram enviadas, reduzidas e guardadas corretamente —
// e não apareciam. O URL respondia 200 com a imagem, o documento tinha o
// `photoUrl` certo, e na app via-se as iniciais como se não houvesse
// foto nenhuma.
//
// A razão: o Flutter web **não usa um `<img>`**. Busca os bytes para os
// descodificar ele próprio, e isso é um pedido sujeito a CORS. Sem
// `Access-Control-Allow-Origin` na resposta, o browser bloqueia-o, o
// `errorBuilder` dispara e o avatar cai nas iniciais — o mesmo que
// aconteceria se a foto não existisse. Daí ser tão difícil de
// diagnosticar de fora: tudo o que se vê é "não aparece".
//
// Um bucket do Firebase Storage nasce **sem** configuração de CORS.
// Nunca ninguém a pôs, por isso nenhuma imagem nem vídeo servido do
// Storage alguma vez funcionou na web — nem os avatares nem os vídeos de
// demonstração dos exercícios.
//
// ## Porquê `*`
//
// Porque aqui o CORS não é uma barreira de acesso, e fingir que é seria
// enganarmo-nos. Estes URLs já são publicamente buscáveis por qualquer
// servidor: quem os tem, tem o ficheiro — o segredo é o token que vai no
// endereço, não a origem do pedido. O CORS só limita o que o JavaScript
// de OUTRO site pode ler no browser, e um site que queira mostrar a foto
// consegue-o à mesma através do seu próprio servidor.
//
// Restringir às origens de produção dava a mesma segurança (nenhuma) e
// partia o desenvolvimento local, onde o servidor do Flutter escolhe uma
// porta diferente a cada arranque e as origens têm de bater certo até à
// porta.
//
//   gcloud auth application-default login   (uma vez)
//   node set-storage-cors.mjs --project=gym-sas
//
// Sem `--yes` mostra o que ia ficar e não escreve nada.

import { initializeApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectId = arg('project', 'gym-sas');
const bucketName = arg('bucket', `${projectId}.firebasestorage.app`);
const confirmed = process.argv.includes('--yes');

const CORS = [
  {
    origin: ['*'],
    // Só leitura. As escritas (enviar uma foto) usam o SDK do Firebase,
    // que fala com outro endpoint e trata do seu próprio CORS.
    method: ['GET', 'HEAD'],
    responseHeader: ['Content-Type', 'Content-Length', 'Content-Range'],
    maxAgeSeconds: 3600,
  },
];

initializeApp({ projectId, storageBucket: bucketName });
const bucket = getStorage().bucket();

const [metadata] = await bucket.getMetadata();
const atual = metadata.cors ?? [];

console.log(`Bucket: ${bucketName}`);
console.log(
  `CORS atual: ${atual.length === 0 ? '(nenhum)' : JSON.stringify(atual)}`,
);
console.log(`CORS a aplicar: ${JSON.stringify(CORS)}`);

if (!confirmed) {
  console.log('\nSem --yes: nada foi escrito.');
  process.exit(0);
}

await bucket.setCorsConfiguration(CORS);

const [depois] = await bucket.getMetadata();
console.log('\n✓ aplicado:', JSON.stringify(depois.cors));
