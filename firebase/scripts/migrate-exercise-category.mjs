// Passa `muscleGroup` (campo antigo) a `category` nos exercícios.
//
// ## Porquê
//
// As categorias deixaram de ser uma lista fixa de grupos musculares e
// passaram a ser do estúdio. Os exercícios do catálogo vêm corrigidos
// pelo `seed-content.mjs`, porque têm ids determinísticos e são
// reescritos por cima.
//
// Os exercícios criados **pela app** não. Nascem com um id aleatório, o
// seed não sabe que existem, e ficam com o campo antigo para sempre.
//
// Este foi o passo que faltava: o `check-deploy` marcava o problema mas
// mandava correr o seed, que não podia resolvê-lo. Correr um comando,
// vê-lo dizer sucesso e ver o verificador continuar vermelho é a forma
// mais rápida de ensinar alguém a ignorar o verificador.
//
// Um exercício sem `category` não desaparece — a app trata a ausência
// como "sem categoria" — mas fica fora de qualquer filtro por
// categoria, que é onde as pessoas o vão procurar.
//
// É idempotente: só toca em documentos sem `category`, e apaga o campo
// antigo para não voltar a aparecer.
//
//   node migrate-exercise-category.mjs --project=<id> --tenant=<tenant> --yes
//
// Sem `--yes` diz o que ia fazer e não faz nada.

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

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

const exercises = firestore
  .collection('tenants')
  .doc(tenantId)
  .collection('exercises');

const snapshot = await exercises.get();
const antigos = snapshot.docs.filter((doc) => !doc.get('category'));

console.log(
  `${snapshot.size} exercício(s); ${antigos.length} sem categoria` +
    `${usingEmulator ? ' [EMULADOR]' : ' [PROJETO REAL]'}.`,
);

for (const doc of antigos) {
  const antigo = doc.get('muscleGroup');
  console.log(
    `  ${doc.get('name') ?? doc.id} → ` +
      (antigo ? `"${antigo}"` : 'sem campo antigo, fica "Sem categoria"'),
  );
}

if (antigos.length === 0) {
  console.log('Nada a fazer.');
  process.exit(0);
}

if (!confirmed) {
  console.log('Sem --yes: nada foi escrito.');
  process.exit(0);
}

const CHUNK = 400;
let escritos = 0;
for (let i = 0; i < antigos.length; i += CHUNK) {
  const batch = firestore.batch();
  for (const doc of antigos.slice(i, i + CHUNK)) {
    const antigo = doc.get('muscleGroup');
    batch.update(doc.ref, {
      // Sem campo antigo não há nada a aproveitar, e deixá-lo vazio
      // devolvia o documento ao mesmo estado. "Sem categoria" é
      // editável pela app como qualquer outra.
      category:
        typeof antigo === 'string' && antigo.trim() !== ''
          ? antigo.trim()
          : 'Sem categoria',
      muscleGroup: FieldValue.delete(),
    });
  }
  await batch.commit();
  escritos += Math.min(CHUNK, antigos.length - i);
  console.log(`  ${escritos}/${antigos.length}`);
}

console.log(`Feito: ${escritos} exercício(s) atualizado(s).`);
