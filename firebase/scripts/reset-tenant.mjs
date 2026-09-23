// Esvaziar um estúdio para arrancar em produção — ficando só o Gestor.
//
// ## Porque isto existe
//
// A base de dados de produção está cheia de dados de demonstração:
// alunos inventados, aulas geradas, planos de exemplo, marcações,
// avaliações, pagamentos. Nada disso pode ficar quando o estúdio
// verdadeiro abrir a app pela primeira vez, e apagar à mão pela consola
// não é opção: os documentos têm SUBCOLEÇÕES (as marcações vivem dentro
// da ocorrência, as avaliações dentro do membro), e apagar um documento
// no Firestore NÃO apaga o que está por baixo. Ficariam órfãos
// invisíveis na consola e bem vivos nas queries de grupo de coleção.
//
// ## O que fica
//
//   * o documento do estúdio (`tenants/{id}`);
//   * o Gestor indicado em `--keep-manager`: o documento em `staff`, o
//     que está em `staff/{id}/private`, a conta de Auth e os custom
//     claims (`tenantId` + `roles`), que são o que lhe dá entrada;
//   * o que for pedido em `--keep=` (ver abaixo).
//
// ## O que desaparece
//
// Tudo o resto por baixo de `tenants/{id}`, recursivamente — incluindo
// os restantes membros e staff. As contas de Auth correspondentes vão
// atrás: uma conta que se autentica e não tem documento nenhum entra
// num estado que nenhum ecrã trata, o que é pior do que não existir.
// Também limpa `_rateLimits` (estado efémero, por uid) e os ficheiros
// do Storage do estúdio (fotos de perfil, media dos exercícios).
//
// ## O catálogo, e porque é que `--keep` existe
//
// Os exercícios, as categorias e as modalidades NÃO são dados do
// cliente: são catálogo genérico, e voltam com um comando
// (`seed-content.mjs`). Por omissão vão abaixo com o resto. Se o estúdio
// já andou a criar exercícios próprios, guarda-os:
//
//   --keep=exercises,exerciseCategories,modalities
//
// `--keep=config` guarda as definições (política de marcação, horizonte
// de dias). Sem elas a app usa os valores por omissão e o Gestor volta a
// pô-las no ecrã das definições. Atenção a este: o `bookingPolicy` tem
// lá dentro um `freeTrainingServiceId` que aponta para um documento de
// `services` — se guardares o `config` e apagares os `services`, fica a
// apontar para nada, e o treino livre deixa de encontrar o seu serviço.
// Guardar o `config` só faz sentido com `--keep=config,services`.
//
// ## Correr
//
//   gcloud auth application-default login          (uma vez)
//   node reset-tenant.mjs --project=gym-sas \
//     --tenant=nxt_performance_studio \
//     --keep-manager=leo@exemplo.pt
//
// Sem `--yes` NÃO APAGA NADA: conta o que está lá e mostra a lista. É
// para se ver a lista antes, não depois. Com `--yes` é definitivo — o
// Firestore não tem lixo nem desfazer.

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectId = arg('project');
const tenantId = arg('tenant');
const managerEmail = arg('keep-manager');
const bucketName = arg('bucket', `${projectId}.firebasestorage.app`);
const manter = new Set(
  (arg('keep', '') || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
);
const confirmado = process.argv.includes('--yes');

const emFalta = Object.entries({
  project: projectId,
  tenant: tenantId,
  'keep-manager': managerEmail,
})
  .filter(([, v]) => !v)
  .map(([k]) => `--${k}`);

if (emFalta.length > 0) {
  console.error(`Faltam argumentos: ${emFalta.join(', ')}`);
  console.error('Ver o cabeçalho deste ficheiro para o comando completo.');
  process.exit(1);
}

initializeApp({ projectId, storageBucket: bucketName });
const firestore = getFirestore();
const auth = getAuth();
const tenantRef = firestore.collection('tenants').doc(tenantId);

const noEmulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

// ---------------------------------------------------------------- Gestor
//
// Isto vem primeiro e é bloqueante de propósito. Criar staff pela app
// exige já ser Gestor, e a consola do Firebase não sabe atribuir custom
// claims — se a conta que se pretende guardar não existir, o resultado
// de apagar o resto é um estúdio onde ninguém consegue entrar, e a única
// saída é voltar a correr `create-first-manager.mjs`. Mais vale parar
// aqui, com os dados ainda de pé.

let gestor;
try {
  gestor = await auth.getUserByEmail(managerEmail);
} catch {
  console.error(`Não existe nenhuma conta com o email "${managerEmail}".`);
  console.error('Cria o Gestor primeiro: ver create-first-manager.mjs.');
  process.exit(1);
}

const claims = gestor.customClaims ?? {};
const papeis = Array.isArray(claims.roles) ? claims.roles : [];
if (claims.tenantId !== tenantId || !papeis.includes('manager')) {
  console.error(
    `"${managerEmail}" existe mas não é Gestor de "${tenantId}".\n` +
      `  tenantId no token: ${claims.tenantId ?? '(nenhum)'}\n` +
      `  roles no token:    ${papeis.length > 0 ? papeis.join(', ') : '(nenhum)'}`,
  );
  process.exit(1);
}

const staffDoGestor = await tenantRef.collection('staff').doc(gestor.uid).get();
if (!staffDoGestor.exists) {
  console.error(
    `"${managerEmail}" tem o token certo mas não tem documento em ` +
      `tenants/${tenantId}/staff/${gestor.uid}.\n` +
      'Sem esse documento a app não o reconhece. Corrige antes de apagar.',
  );
  process.exit(1);
}

// -------------------------------------------------------------- Inventário

const coleccoes = await tenantRef.listCollections();
const paraApagar = [];
const guardadas = [];

for (const col of coleccoes) {
  if (manter.has(col.id)) {
    guardadas.push(col.id);
    continue;
  }
  const docs = await col.listDocuments();
  paraApagar.push({ id: col.id, ref: col, docs });
}

// `staff` é o único caso em que não se apaga a coleção inteira.
const staff = paraApagar.find((c) => c.id === 'staff');
const staffAApagar = staff ? staff.docs.filter((d) => d.id !== gestor.uid) : [];

// As contas de Auth: as que têm o estúdio no token, mais as que vêm dos
// documentos que vão abaixo (uma conta cujo documento já tinha sido
// apagado à mão não aparece na segunda lista, e é precisamente essa que
// interessa apanhar).
const uidsDeDocumentos = new Set();
for (const col of paraApagar) {
  if (col.id !== 'members' && col.id !== 'staff') continue;
  for (const doc of col.docs) uidsDeDocumentos.add(doc.id);
}

const contas = new Map();
let pagina = await auth.listUsers(1000);
for (;;) {
  for (const u of pagina.users) {
    if ((u.customClaims?.tenantId ?? null) === tenantId) contas.set(u.uid, u.email ?? u.uid);
  }
  if (!pagina.pageToken) break;
  pagina = await auth.listUsers(1000, pagina.pageToken);
}
for (const uid of uidsDeDocumentos) {
  if (!contas.has(uid)) contas.set(uid, uid);
}
contas.delete(gestor.uid);

// Storage: as fotos de perfil e a media dos exercícios deste estúdio.
let ficheiros = [];
if (!noEmulador) {
  const bucket = getStorage().bucket();
  const [todos] = await bucket.getFiles({ prefix: `tenants/${tenantId}/` });
  ficheiros = todos.filter((f) => {
    if (f.name.startsWith(`tenants/${tenantId}/avatars/${gestor.uid}/`)) return false;
    if (manter.has('exercises') && f.name.startsWith(`tenants/${tenantId}/exercises/`)) {
      return false;
    }
    return true;
  });
}

const limites = await firestore.collection('_rateLimits').listDocuments();

// ------------------------------------------------------------------ Aviso

console.log('');
console.log(`Projeto:  ${projectId}${noEmulador ? '  [EMULADOR]' : '  [PROJETO REAL]'}`);
console.log(`Estúdio:  ${tenantId}`);
console.log(`Fica:     ${managerEmail}  (${gestor.uid})`);
console.log('');

console.log(`APAGA em tenants/${tenantId}:`);
for (const col of paraApagar) {
  const n = col.id === 'staff' ? staffAApagar.length : col.docs.length;
  const nota = col.id === 'staff' ? '  (o Gestor fica)' : '';
  console.log(`  ${col.id.padEnd(24)} ${String(n).padStart(5)} doc(s)${nota}`);
}
if (paraApagar.length === 0) console.log('  (nada)');
console.log('');
console.log(`APAGA contas de Auth:      ${String(contas.size).padStart(5)}`);
console.log(`APAGA ficheiros (Storage): ${String(ficheiros.length).padStart(5)}`);
console.log(`APAGA _rateLimits:         ${String(limites.length).padStart(5)}`);
if (guardadas.length > 0) {
  console.log('');
  console.log(`GUARDA (--keep): ${guardadas.join(', ')}`);
}

// Os documentos de topo são a ponta do icebergue: as marcações estão
// dentro das ocorrências, as avaliações dentro dos membros. `--verbose`
// mostra quem são as contas, que é o que costuma dar vontade de
// confirmar antes de carregar no botão.
console.log('');
console.log('As subcoleções vão atrás (marcações, presenças, avaliações, ...).');

if (process.argv.includes('--verbose') && contas.size > 0) {
  console.log('');
  console.log('Contas que vão abaixo:');
  for (const email of [...contas.values()].sort()) console.log(`  ${email}`);
}

if (!confirmado) {
  console.log('');
  console.log('Não foi apagado nada. Para apagar mesmo, repete com --yes.');
  process.exit(0);
}

// ------------------------------------------------------------------ Apagar

console.log('');
for (const col of paraApagar) {
  if (col.id === 'staff') {
    for (const doc of staffAApagar) await firestore.recursiveDelete(doc);
    console.log(`  ${'staff'.padEnd(24)} ${staffAApagar.length} apagado(s)`);
    continue;
  }
  await firestore.recursiveDelete(col.ref);
  console.log(`  ${col.id.padEnd(24)} ${col.docs.length} apagado(s)`);
}

if (contas.size > 0) {
  const uids = [...contas.keys()];
  for (let i = 0; i < uids.length; i += 1000) {
    await auth.deleteUsers(uids.slice(i, i + 1000));
  }
  console.log(`  ${'contas de Auth'.padEnd(24)} ${uids.length} apagada(s)`);
}

if (ficheiros.length > 0) {
  await Promise.all(ficheiros.map((f) => f.delete({ ignoreNotFound: true })));
  console.log(`  ${'ficheiros do Storage'.padEnd(24)} ${ficheiros.length} apagado(s)`);
}

for (const doc of limites) await doc.delete();
if (limites.length > 0) {
  console.log(`  ${'_rateLimits'.padEnd(24)} ${limites.length} apagado(s)`);
}

console.log('');
console.log('Feito. O estúdio está vazio e o Gestor entra na app normalmente.');
console.log('A seguir, se fizer sentido:');
console.log(`  node seed-content.mjs --project=${projectId} --tenant=${tenantId} --yes`);
console.log('    repõe o catálogo de exercícios, categorias e modalidades.');
console.log(`  node seed-review-account.mjs --project=${projectId} --tenant=${tenantId} --yes`);
console.log('    cria a conta de demonstração para a App Store / Play Store.');
