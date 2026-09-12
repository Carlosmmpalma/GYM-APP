// Confirma que o que está no código está MESMO publicado.
//
// ## Porque isto existe
//
// `firebase deploy` diz "sucesso" quando publica o que lhe pediste — não
// quando publica tudo o que era preciso. Publicar as funções e esquecer
// os índices dá dois sucessos e uma app partida, e não há nada no
// terminal que o denuncie.
//
// Foi o que aconteceu: a certa altura tínhamos a base de dados com os
// índices de ontem, as funções de anteontem e o site de hoje, e a única
// forma de saber foi comparar tudo à mão. Isto é essa comparação, feita
// por um script.
//
// ## O que verifica, e como
//
// Onde pode, verifica **comportamento** e não configuração — porque a
// pergunta não é "o ficheiro foi enviado?" mas "a app funciona?". Um
// índice declarado e ainda a construir é indistinguível de um índice
// publicado se olhares só para a lista; a diferença vê-se quando corres
// a query.
//
//   1. FUNÇÕES     · compara o build local com o que está publicado.
//   2. ÍNDICES     · compara a declaração, e depois CORRE as queries que
//                    dependem deles — é isso que prova que já acabaram
//                    de construir.
//   3. REGRAS      · lê sem sessão o que deve ser público, e tenta ler
//                    sem sessão o que não deve. As duas coisas juntas
//                    provam que as regras novas estão em vigor.
//   4. SITE        · busca o index.html publicado e procura o ecrã de
//                    arranque e a build wasm.
//   5. MIGRAÇÕES   · confirma que os passos de "correr uma vez" correram
//                    mesmo: catálogo, campo dos lembretes, vitrina,
//                    conta de revisão.
//
// Não escreve nada. Pode correr as vezes que quiseres.
//
//   gcloud auth application-default login   (uma vez)
//   node check-deploy.mjs --project=gym-sas --tenant=nxt_performance_studio

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RAIZ = path.resolve(__dirname, '../..');

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectId = arg('project', 'gym-sas');
const tenantId = arg('tenant', 'nxt_performance_studio');
const siteUrl = arg('site', `https://${projectId}.web.app`);

// ---------------------------------------------------------------------
// Relatório
// ---------------------------------------------------------------------
const problemas = [];
const avisos = [];

function ok(msg) {
  console.log(`  [32m✓[0m ${msg}`);
}
function falha(msg, comoResolver) {
  console.log(`  [31m✗[0m ${msg}`);
  problemas.push({ msg, comoResolver });
}
function aviso(msg, nota) {
  console.log(`  [33m![0m ${msg}`);
  avisos.push({ msg, nota });
}
function titulo(t) {
  console.log(`\n[1m${t}[0m`);
}

function semAnsi(texto) {
  // eslint-disable-next-line no-control-regex
  return texto.replace(/\[[0-9;]*m/g, '');
}

function firebaseCli(args) {
  // `shell: true` no Windows: o `firebase` é um `.cmd`, e o `execFile`
  // sem shell recusa-o com EINVAL.
  return semAnsi(
    execFileSync(
      'firebase',
      [...args, `--project=${projectId}`],
      {
        encoding: 'utf8',
        maxBuffer: 20 * 1024 * 1024,
        shell: process.platform === 'win32',
      },
    ),
  );
}

// O `lib/index.js` chama `initializeApp()` ao ser carregado, e sem isto
// recusa-se a arrancar — o que fazia a comparação das funções falhar por
// uma razão que nada tinha a ver com o que se quer saber.
process.env.GCLOUD_PROJECT ??= projectId;

console.log(
  `A verificar "${projectId}" (tenant "${tenantId}") contra o código local.`,
);

// ---------------------------------------------------------------------
// 1. Funções
// ---------------------------------------------------------------------
titulo('1. Cloud Functions');
try {
  // `pathToFileURL`: no Windows, `import('C:\...')` é recusado — o
  // `import()` dinâmico só aceita URLs.
  let modulo = null;
  let motivo = null;
  try {
    modulo = await import(
      pathToFileURL(path.join(RAIZ, 'firebase/functions/lib/index.js')).href
    );
  } catch (erro) {
    motivo = erro.message.split(String.fromCharCode(10))[0];
  }

  if (!modulo) {
    aviso(
      `Não consegui ler \`firebase/functions/lib/index.js\`: ${motivo}`,
      'Corre `npm --prefix firebase/functions run build` primeiro.',
    );
  } else {
    // `__esModule` e `default` são artefactos da interoperabilidade
    // CommonJS/ESM, não funções — sem isto apareciam como "por publicar"
    // para sempre.
    const locais = Object.keys(modulo)
      .filter((nome) => nome !== '__esModule' && nome !== 'default')
      .sort();
    const tabela = firebaseCli(['functions:list']);
    const publicadas = new Set(
      tabela
        .split('\n')
        .map((linha) => linha.match(/^│\s+([a-zA-Z][a-zA-Z0-9]*)\s/))
        .filter(Boolean)
        .map((m) => m[1]),
    );

    const faltam = locais.filter((f) => !publicadas.has(f));
    if (faltam.length === 0) {
      ok(`${locais.length} funções, todas publicadas`);
    } else {
      falha(
        `${faltam.length} função(ões) por publicar: ${faltam.join(', ')}`,
        `firebase deploy --only functions --project=${projectId}`,
      );
    }

    // Funções publicadas que já não existem no código continuam a poder
    // ser chamadas, e a custar dinheiro em arranques a frio.
    const orfas = [...publicadas].filter(
      (f) => !locais.includes(f) && f !== 'Function',
    );
    if (orfas.length > 0) {
      aviso(
        `publicadas mas já não existem no código: ${orfas.join(', ')}`,
        'Apaga-as com `firebase functions:delete <nome>` — continuam a ser ' +
          'chamáveis enquanto existirem.',
      );
    }
  }
} catch (erro) {
  aviso(`não consegui comparar as funções: ${erro.message}`);
}

// ---------------------------------------------------------------------
// 2. Índices
// ---------------------------------------------------------------------
titulo('2. Índices do Firestore');

function chaveIndice(ix) {
  const campos = (ix.fields ?? [])
    .filter((f) => f.fieldPath !== '__name__')
    .map((f) => `${f.fieldPath}:${f.order ?? f.arrayConfig}`)
    .join('+');
  return `${ix.collectionGroup}|${ix.queryScope}|${campos}`;
}

try {
  const local = JSON.parse(
    readFileSync(path.join(RAIZ, 'firestore.indexes.json'), 'utf8'),
  );
  const bruto = firebaseCli(['firestore:indexes']);
  const remoto = JSON.parse(bruto.slice(bruto.indexOf('{')));

  const publicados = new Set((remoto.indexes ?? []).map(chaveIndice));
  const faltam = (local.indexes ?? []).filter(
    (ix) => !publicados.has(chaveIndice(ix)),
  );

  if (faltam.length === 0) {
    ok(`${local.indexes.length} índices compostos declarados e publicados`);
  } else {
    falha(
      `${faltam.length} índice(s) por publicar: ` +
        faltam.map((ix) => chaveIndice(ix).replace(/\|/g, ' ')).join(' · '),
      `firebase deploy --only firestore:indexes --project=${projectId}`,
    );
  }

  const chaveFO = (fo) => `${fo.collectionGroup}.${fo.fieldPath}`;
  const foPublicados = new Set((remoto.fieldOverrides ?? []).map(chaveFO));
  const foFaltam = (local.fieldOverrides ?? []).filter(
    (fo) => !foPublicados.has(chaveFO(fo)),
  );
  if (foFaltam.length === 0) {
    ok(`${local.fieldOverrides.length} exceções de campo publicadas`);
  } else {
    falha(
      `${foFaltam.length} exceção(ões) de campo por publicar: ` +
        foFaltam.map(chaveFO).join(', '),
      `firebase deploy --only firestore:indexes --project=${projectId}`,
    );
  }
} catch (erro) {
  aviso(`não consegui comparar os índices: ${erro.message}`);
}

// ---------------------------------------------------------------------
// Admin SDK — daqui para baixo é preciso ler dados a sério.
// ---------------------------------------------------------------------
initializeApp({ projectId });
const firestore = getFirestore();
const auth = getAuth();
const tenantRef = firestore.collection('tenants').doc(tenantId);

titulo('3. Índices em uso (não só declarados)');
// Um índice declarado e ainda A CONSTRUIR é indistinguível de um
// publicado se olhares só para a lista. A diferença só se vê a correr a
// query: sem índice pronto, o Firestore devolve FAILED_PRECONDITION.
const queries = [
  {
    nome: 'lembretes (status + reminderSentAt + startAt)',
    correr: () =>
      tenantRef
        .collection('sessionOccurrences')
        .where('status', '==', 'scheduled')
        .where('reminderSentAt', '==', null)
        .where('startAt', '>=', Timestamp.now())
        .limit(1)
        .get(),
  },
  {
    // Dentro de UM membro, e não em grupo de coleções: é assim que a app
    // as consulta, e o índice declarado é de âmbito COLLECTION. Uma
    // sonda em grupo falharia por falta de um índice que não existe nem
    // é preciso — e diria que estava tudo mal.
    nome: 'histórico de carga (exerciseId + recordedAt)',
    precisaDeMembro: true,
    correr: (membro) =>
      membro
        .collection('loadHistory')
        .where('exerciseId', '==', '__sonda__')
        .orderBy('recordedAt', 'desc')
        .limit(1)
        .get(),
  },
  {
    nome: 'treino em curso (finishedAt + startedAt)',
    precisaDeMembro: true,
    correr: (membro) =>
      membro
        .collection('workoutSessions')
        .where('finishedAt', '==', null)
        .orderBy('startedAt', 'desc')
        .limit(1)
        .get(),
  },
  {
    nome: 'subscrições por plano (planId + status)',
    correr: () =>
      tenantRef
        .collection('subscriptions')
        .where('planId', '==', '__sonda__')
        .where('status', '==', 'active')
        .limit(1)
        .get(),
  },
];

// Um membro qualquer, para as sondas que consultam subcoleções dele.
const algumMembro = (await tenantRef.collection('members').limit(1).get())
  .docs[0]?.ref;

for (const q of queries) {
  if (q.precisaDeMembro && !algumMembro) {
    aviso(`${q.nome} — sem membros para sondar`);
    continue;
  }
  try {
    await q.correr(algumMembro);
    ok(`${q.nome} — a query corre`);
  } catch (erro) {
    const emConstrucao = /building|currently building/i.test(erro.message);
    const semIndice = /requires an index|FAILED_PRECONDITION/i.test(
      erro.message,
    );
    falha(
      `${q.nome} — ${
        emConstrucao
          ? 'índice ainda A CONSTRUIR'
          : semIndice
            ? 'índice em falta'
            : `a query falha: ${erro.message.split(String.fromCharCode(10))[0].slice(0, 90)}`
      }`,
      emConstrucao
        ? 'Espera que termine na consola do Firestore antes de publicar o site.'
        : `firebase deploy --only firestore:indexes --project=${projectId}`,
    );
  }
}

// ---------------------------------------------------------------------
// 4. Regras — por comportamento, sem sessão
// ---------------------------------------------------------------------
titulo('4. Security Rules em vigor');

const apiKey = (() => {
  const ficheiro = readFileSync(
    path.join(RAIZ, 'lib/infrastructure/config/firebase_options_production.dart'),
    'utf8',
  );
  const m = ficheiro.match(/apiKey:\s*'([^']+)'/);
  return m ? m[1] : null;
})();

async function lerSemSessao(caminho) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/(default)/documents/${caminho}?key=${apiKey}`;
  const resposta = await fetch(url);
  return resposta.status;
}

if (!apiKey) {
  aviso('não encontrei a apiKey de produção — saltei a verificação de regras');
} else {
  // A vitrina TEM de se ler sem sessão: é a condição de o ecrã público
  // existir.
  const publico = await lerSemSessao(
    `tenants/${tenantId}/public/schedule`,
  ).catch(() => 0);
  if (publico === 200) {
    ok('a vitrina lê-se sem sessão (regras novas em vigor)');
  } else if (publico === 404) {
    aviso(
      'as regras deixam ler a vitrina, mas o documento ainda não existe',
      'Corre a geração de aulas — ver a secção das migrações abaixo.',
    );
  } else {
    falha(
      `a vitrina NÃO se lê sem sessão (HTTP ${publico})`,
      `firebase deploy --only firestore:rules --project=${projectId}`,
    );
  }

  // E o resto TEM de continuar fechado. Sem isto, "as regras novas estão
  // lá" podia querer dizer "as regras abriram tudo".
  const privado = await lerSemSessao(`tenants/${tenantId}`).catch(() => 0);
  if (privado === 403 || privado === 401) {
    ok('o resto do tenant continua fechado sem sessão');
  } else {
    falha(
      `o documento do tenant responde ${privado} sem sessão — devia recusar`,
      'Revê `firestore.rules`: a abertura da vitrina não pode ter alastrado.',
    );
  }
}

// ---------------------------------------------------------------------
// 5. Site publicado
// ---------------------------------------------------------------------
titulo('5. Site publicado');
try {
  const index = await fetch(`${siteUrl}/index.html`, {
    cache: 'no-store',
  }).then((r) => r.text());

  if (index.includes('id="splash"')) {
    ok('o ecrã de arranque está publicado');
  } else {
    falha(
      'o index.html publicado não tem o ecrã de arranque',
      'Compila e publica: `flutter build web --release --wasm ' +
        '-t lib/main_production.dart` e `firebase deploy --only hosting`.',
    );
  }

  const bootstrap = await fetch(`${siteUrl}/flutter_bootstrap.js`, {
    cache: 'no-store',
  }).then((r) => r.text());

  // `"compileTarget":"dart2wasm"` e não só `dart2wasm`: a palavra existe
  // dentro do próprio carregador (`e.compileTarget==="dart2wasm"`), por
  // isso a procura ingénua dava verde numa build que era só JavaScript.
  // Um verificador que mente é pior do que não ter nenhum.
  if (bootstrap.includes('"compileTarget":"dart2wasm"')) {
    ok('a build publicada inclui a versão WebAssembly');
  } else {
    aviso(
      'a build publicada é só JavaScript',
      'Foi compilada sem `--wasm`. Funciona, mas transfere mais 1,1 MB.',
    );
  }
  if (bootstrap.includes('__removerSplash')) {
    ok('o arranque publicado sabe tirar o ecrã de arranque');
  } else {
    falha(
      'o flutter_bootstrap.js publicado não tira o ecrã de arranque',
      'Publica o hosting outra vez a partir de uma build nova.',
    );
  }
} catch (erro) {
  aviso(`não consegui buscar o site (${erro.message})`);
}

// ---------------------------------------------------------------------
// 6. Migrações de "correr uma vez"
// ---------------------------------------------------------------------
titulo('6. Passos que se correm uma vez');

// Catálogo de exercícios: `muscleGroup` deixou de existir quando as
// categorias passaram a ser do estúdio.
//
// O remédio NÃO é o seed. O seed reescreve os 61 exercícios do catálogo,
// que têm ids determinísticos — não vê os que o estúdio criou pela app,
// que são os únicos que podem ter ficado para trás. Isto já esteve
// errado aqui, e o sintoma foi correr o comando sugerido, ver "✓ 61
// exercícios" e o verificador continuar vermelho.
// Sem `limit`: com 63 exercícios e um limite de 50, treze nunca eram
// olhados — e o que escapa a um verificador é exatamente o que fica por
// corrigir. Um catálogo é pequeno e isto corre raramente.
const exercicios = await tenantRef.collection('exercises').get();
if (exercicios.empty) {
  aviso(
    'não há exercícios neste tenant',
    `node firebase/scripts/seed-content.mjs --project=${projectId} ` +
      `--tenant=${tenantId} --yes`,
  );
} else {
  const semCategoria = exercicios.docs.filter((d) => !d.get('category'));
  if (semCategoria.length === 0) {
    ok(`${exercicios.size} exercícios, todos com categoria`);
  } else {
    falha(
      `${semCategoria.length} exercício(s) sem categoria (campo antigo): ` +
        semCategoria.map((d) => d.get('name') ?? d.id).join(', '),
      `node firebase/scripts/migrate-exercise-category.mjs ` +
        `--project=${projectId} --tenant=${tenantId} --yes`,
    );
  }
}

// Lembretes: o Firestore não encontra `== null` onde o campo não existe,
// por isso uma aula sem ele nunca recebe aviso — em silêncio.
//
// O limite fica — um estúdio grande pode ter muitas aulas futuras e isto
// paga-se por leitura — mas passou a dizer quando trunca. Um verificador
// que olha para uma parte e dá um ✓ sobre o todo é pior do que não
// verificar: dá a resposta errada com a mesma confiança.
const TETO_FUTURAS = 500;
const futuras = await tenantRef
  .collection('sessionOccurrences')
  .where('startAt', '>=', Timestamp.now())
  .limit(TETO_FUTURAS)
  .get();
if (futuras.empty) {
  aviso('não há aulas futuras — nada para avisar nem para mostrar na vitrina');
} else {
  const semCampo = futuras.docs.filter(
    (d) => d.get('reminderSentAt') === undefined,
  );
  if (semCampo.length === 0) {
    const truncou = futuras.size === TETO_FUTURAS;
    ok(
      `${futuras.size}${truncou ? '+' : ''} aulas futuras, ` +
        'todas com `reminderSentAt`' +
        (truncou ? ` (só as primeiras ${TETO_FUTURAS} foram vistas)` : ''),
    );
  } else {
    falha(
      `${semCampo.length} aula(s) futura(s) sem \`reminderSentAt\` — nunca ` +
        'receberão lembrete',
      `node firebase/scripts/backfill-reminder-field.mjs --project=${projectId} ` +
        `--tenant=${tenantId} --yes`,
    );
  }
}

// Vitrina: mapa de aulas.
const schedule = await tenantRef.collection('public').doc('schedule').get();
if (!schedule.exists) {
  falha(
    'a vitrina não tem mapa de aulas',
    'Abre a app como Gestor e usa "Gerar agora" em Aulas/Horários, ou ' +
      'espera pelo cron das 03:00.',
  );
} else {
  const escrito = schedule.get('updatedAt')?.toDate?.();
  const dias = escrito
    ? Math.floor((Date.now() - escrito.getTime()) / 86_400_000)
    : null;
  const entradas = (schedule.get('entries') ?? []).length;
  if (dias !== null && dias > 7) {
    falha(
      `o mapa de aulas não é reescrito há ${dias} dias — a app esconde-o`,
      'O cron diário parou. Vê os logs de `generateRecurringOccurrences`.',
    );
  } else if (entradas === 0) {
    aviso(
      'o mapa de aulas está publicado mas vazio',
      'Não há séries ativas. A vitrina não o mostra.',
    );
  } else {
    ok(`mapa de aulas com ${entradas} aula(s), escrito há ${dias ?? '?'} dia(s)`);
  }
}

// Vitrina: informação do estúdio.
const info = await tenantRef.collection('public').doc('info').get();
const emFalta = [];
if (!info.exists) {
  emFalta.push('tudo');
} else {
  const campo = (n) => (info.get(n) ?? '').toString().trim();
  if (!campo('privacyPolicyUrl')) emFalta.push('política de privacidade');
  if (!campo('address')) emFalta.push('morada');
  if (!campo('phone')) emFalta.push('telefone');
  if (!campo('email')) emFalta.push('email');
  if (((info.get('openingHours') ?? []).length ?? 0) === 0) {
    emFalta.push('horário');
  }
}
if (emFalta.length === 0) {
  ok('informação pública do estúdio preenchida');
} else if (emFalta.includes('política de privacidade') || !info.exists) {
  falha(
    `informação pública por preencher: ${emFalta.join(', ')}`,
    'Abre a app como Gestor em Gestão › Informação pública. Sem a política ' +
      'de privacidade não há submissão possível nas lojas.',
  );
} else {
  aviso(
    `informação pública incompleta: ${emFalta.join(', ')}`,
    'Gestão › Informação pública. O que falta não aparece na vitrina.',
  );
}

// Conta de revisão.
const revisao = await tenantRef
  .collection('members')
  .where('isReviewAccount', '==', true)
  .limit(1)
  .get();
if (revisao.empty) {
  aviso(
    'não existe conta de revisão para as lojas',
    `node firebase/scripts/seed-review-account.mjs --project=${projectId} ` +
      `--tenant=${tenantId} --yes`,
  );
} else {
  const doc = revisao.docs[0];
  const [marcacoes, treinos] = await Promise.all([
    firestore
      .collectionGroup('bookings')
      .where('memberId', '==', doc.id)
      .where('status', '==', 'booked')
      .count()
      .get(),
    doc.ref.collection('workouts').count().get(),
  ]);
  const nMarcacoes = marcacoes.data().count;
  const nTreinos = treinos.data().count;
  // Uma conta vazia é quase o mesmo que não ter conta nenhuma: o
  // reviewer entra e não vê produto nenhum.
  if (nMarcacoes === 0 || nTreinos === 0) {
    falha(
      `a conta de revisão (nº ${doc.get('memberNumber')}) está vazia — ` +
        `${nMarcacoes} marcações, ${nTreinos} treinos`,
      `node firebase/scripts/seed-review-account.mjs --project=${projectId} ` +
        `--tenant=${tenantId} --yes`,
    );
  } else {
    ok(
      `conta de revisão nº ${doc.get('memberNumber')} — ${nMarcacoes} ` +
        `marcações, ${nTreinos} treinos`,
    );
  }
  try {
    const utilizador = await auth.getUser(doc.id);
    if (utilizador.disabled) {
      falha('a conta de revisão está DESATIVADA no Auth', 'Reativa-a.');
    }
  } catch {
    falha(
      'a conta de revisão tem documento mas já não tem login no Auth',
      `node firebase/scripts/seed-review-account.mjs --project=${projectId} ` +
        `--tenant=${tenantId} --yes`,
    );
  }
}

// ---------------------------------------------------------------------
// Fim
// ---------------------------------------------------------------------
console.log('\n' + '─'.repeat(64));
if (problemas.length === 0 && avisos.length === 0) {
  console.log('[32mTudo o que está no código está publicado.[0m');
  process.exit(0);
}

if (problemas.length > 0) {
  console.log(`\n[31mPor resolver (${problemas.length}):[0m`);
  for (const p of problemas) {
    console.log(`\n  ${p.msg}`);
    if (p.comoResolver) console.log(`    → ${p.comoResolver}`);
  }
}
if (avisos.length > 0) {
  console.log(`\n[33mA confirmar (${avisos.length}):[0m`);
  for (const a of avisos) {
    console.log(`\n  ${a.msg}`);
    if (a.nota) console.log(`    → ${a.nota}`);
  }
}
console.log('');
process.exit(problemas.length > 0 ? 1 : 0);
