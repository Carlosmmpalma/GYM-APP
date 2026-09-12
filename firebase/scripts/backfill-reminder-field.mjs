// Põe `reminderSentAt: null` nas ocorrências que nasceram sem ele.
//
// ## Porquê
//
// Os lembretes passaram a procurar só as aulas por avisar, com
// `where('reminderSentAt', '==', null)` — antes liam as doze vezes que
// cada aula entra na janela e descartavam onze em memória, logo a
// seguir a serem pagas.
//
// O Firestore NÃO encontra `== null` em documentos onde o campo não
// existe. As ocorrências criadas antes desta mudança não o têm, por
// isso ficariam invisíveis para a query — e nunca receberiam lembrete.
// Não há aviso nenhum quando isso acontece: a função corre, não
// encontra nada, e devolve zero.
//
// É idempotente: só escreve onde o campo falta mesmo, e não toca nas
// aulas já avisadas (essas têm um timestamp, que é a marca de "já
// está").
//
// Correr uma vez, depois do deploy das funções:
//
//   node backfill-reminder-field.mjs --project=<id> --tenant=<tenant> --yes
//
// Sem `--yes` diz o que ia fazer e não faz nada.

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

function arg(name) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : undefined;
}

const projectId = arg('project');
const tenantId = arg('tenant');
const confirmed = process.argv.includes('--yes');

if (!projectId || !tenantId) {
  console.error('Faltam argumentos: --project e --tenant.');
  console.error('Ver o cabeçalho deste ficheiro para o comando completo.');
  process.exit(1);
}

const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

initializeApp({ projectId });
const firestore = getFirestore();

const occurrences = firestore
  .collection('tenants')
  .doc(tenantId)
  .collection('sessionOccurrences');

// Só as que ainda interessam. Uma aula que já aconteceu nunca vai
// receber lembrete, e reescrevê-la seria pagar escritas por nada — num
// estúdio com um ano de histórico são milhares.
const snapshot = await occurrences.where('startAt', '>=', new Date()).get();

const missing = snapshot.docs.filter(
  (doc) => doc.get('reminderSentAt') === undefined,
);

console.log(
  `${snapshot.size} ocorrência(s) futura(s); ` +
    `${missing.length} sem o campo` +
    `${usingEmulator ? ' [EMULADOR]' : ' [PROJETO REAL]'}.`,
);

if (missing.length === 0) {
  console.log('Nada a fazer.');
  process.exit(0);
}

if (!confirmed) {
  console.log('Sem --yes: nada foi escrito.');
  process.exit(0);
}

// Em lotes, que é o limite de escritas por batch do Firestore.
const CHUNK = 400;
let written = 0;
for (let i = 0; i < missing.length; i += CHUNK) {
  const batch = firestore.batch();
  for (const doc of missing.slice(i, i + CHUNK)) {
    batch.update(doc.ref, { reminderSentAt: null });
  }
  await batch.commit();
  written += Math.min(CHUNK, missing.length - i);
  console.log(`  ${written}/${missing.length}`);
}

console.log(`Feito: ${written} ocorrência(s) atualizada(s).`);
