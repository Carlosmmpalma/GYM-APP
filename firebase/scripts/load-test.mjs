// Um ginásio a sério, e o cronómetro ligado.
//
// ## Porquê
//
// Tudo o que foi medido até aqui foi medido com o seed de
// desenvolvimento: um punhado de membros, duas aulas, uma série. Nesse
// tamanho tudo é rápido, e a pergunta que interessa — "o que acontece
// quando o estúdio está cheio?" — fica por responder.
//
// O NXT vai ter no máximo 100 sócios. Isto constrói exatamente isso, com
// dois meses de história em cima, e cronometra as operações que doem:
//
//   1. o cron diário que gera as aulas das próximas 8 semanas;
//   2. trinta pessoas a marcarem a MESMA aula ao mesmo tempo;
//   3. o painel de retenção, que a própria docstring chama "a função
//      mais cara do projeto";
//   4. os lembretes de hora a hora;
//   5. as leituras que um Gestor e um Aluno fazem ao abrir a app.
//
// Corre contra o EMULADOR, e recusa-se a correr contra outra coisa: isto
// escreve milhares de documentos e não é para acontecer em produção.
//
//   firebase emulators:start --only firestore,functions,auth,storage
//   node load-test.mjs
//
// `--membros=`, `--series=` e `--concorrentes=` mudam a escala, para
// poder responder à pergunta seguinte ("e com 500?") sem reescrever
// nada.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_carga';
const REGION = 'europe-west1';
const N_MEMBROS = Number(arg('membros', '100'));
const N_SERIES = Number(arg('series', '20'));
const SEMANAS_DE_HISTORIA = Number(arg('historia', '8'));

// Isto escreve milhares de documentos. Contra um projeto real seria um
// estrago, não um teste.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
}
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';
if (!/localhost|127\.0\.0\.1/.test(process.env.FIRESTORE_EMULATOR_HOST)) {
  console.error('Isto só corre contra o emulador. A sair.');
  process.exit(1);
}

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'carga');
const adminAuth = getAdminAuth(adminApp);
const db = getFirestore(adminApp);
const tenantRef = db.doc(`tenants/${TENANT_ID}`);

const SERVICO = 'svc_aulas';
const PLANO = 'plan_2x';

// ---------------------------------------------------------------------
// Cronómetro
// ---------------------------------------------------------------------
const medicoes = [];
async function cronometrar(nome, detalhe, fn) {
  const t0 = process.hrtime.bigint();
  const resultado = await fn();
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  medicoes.push({ nome, detalhe, ms });
  console.log(`  ${ms.toFixed(0).padStart(6)} ms  ${nome}  ${detalhe}`);
  return resultado;
}

/// Escreve em lotes de 400 — o limite do Firestore é 500, e a folga
/// evita ter de pensar nisso a cada chamada.
async function escreverEmLotes(docs) {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const { ref, data } of docs.slice(i, i + 400)) batch.set(ref, data);
    await batch.commit();
  }
}

// ---------------------------------------------------------------------
// 1. Construir o ginásio
// ---------------------------------------------------------------------
console.log(
  `\nA construir um ginásio com ${N_MEMBROS} sócios, ${N_SERIES} séries ` +
    `semanais e ${SEMANAS_DE_HISTORIA} semanas de história.\n`,
);

await db.recursiveDelete(tenantRef);
await tenantRef.set({ name: 'Ginásio de Carga', timeZone: 'Europe/Lisbon' });
await tenantRef
  .collection('services')
  .doc(SERVICO)
  .set({ name: 'Aula de Grupo', active: true });
await tenantRef
  .collection('plans')
  .doc(PLANO)
  .set({ name: '2x por semana', active: true, currentPrice: 45 });
await tenantRef
  .collection('plans')
  .doc(PLANO)
  .collection('services')
  .doc(SERVICO)
  .set({
    serviceId: SERVICO,
    enabled: true,
    usage: { type: 'limited', limit: 2 },
  });

const membros = Array.from({ length: N_MEMBROS }, (_, i) => `carga_m${i}`);

await cronometrar('seed', `${N_MEMBROS} membros + subscrições`, async () => {
  await escreverEmLotes(
    membros.flatMap((uid, i) => [
      {
        ref: tenantRef.collection('members').doc(uid),
        data: {
          name: `Sócio ${i}`,
          memberNumber: String(100000 + i),
          status: 'active',
          phone: '',
          email: '',
        },
      },
      {
        ref: tenantRef.collection('subscriptions').doc(`sub_${uid}`),
        data: {
          memberId: uid,
          planId: PLANO,
          status: 'active',
          activeServiceIds: [SERVICO],
        },
      },
    ]),
  );
});

// Séries espalhadas pela semana, como um horário real: quatro aulas por
// dia, de segunda a sexta.
const horas = ['07:00', '12:30', '18:00', '19:30'];
await cronometrar('seed', `${N_SERIES} séries semanais`, async () => {
  await escreverEmLotes(
    Array.from({ length: N_SERIES }, (_, i) => ({
      ref: tenantRef.collection('sessionSeries').doc(`serie_${i}`),
      data: {
        serviceId: SERVICO,
        instructorId: `instrutor_${i % 3}`,
        modalityId: null,
        dayOfWeek: (i % 5) + 1,
        startTime: horas[i % horas.length],
        durationMinutes: 60,
        capacity: 12,
        startDate: Timestamp.fromDate(
          new Date(Date.now() - SEMANAS_DE_HISTORIA * 7 * 86_400_000),
        ),
        preAssignedMemberIds: [],
        status: 'active',
      },
    })),
  );
});

// História: aulas passadas com marcações e presenças. É isto que o
// painel de retenção percorre.
const aulasPassadas = [];
const marcacoes = [];
const presencas = [];
for (let semana = 1; semana <= SEMANAS_DE_HISTORIA; semana++) {
  for (let i = 0; i < N_SERIES; i++) {
    const quando = new Date(Date.now() - semana * 7 * 86_400_000 + i * 3600_000);
    const id = `passada_${semana}_${i}`;
    const inscritos = membros.slice((i * 7) % N_MEMBROS, ((i * 7) % N_MEMBROS) + 10);
    aulasPassadas.push({
      ref: tenantRef.collection('sessionOccurrences').doc(id),
      data: {
        serviceId: SERVICO,
        instructorId: `instrutor_${i % 3}`,
        modalityId: null,
        seriesId: `serie_${i}`,
        startAt: Timestamp.fromDate(quando),
        endAt: Timestamp.fromDate(new Date(quando.getTime() + 3600_000)),
        capacity: 12,
        status: 'scheduled',
        activeBookingCount: inscritos.length,
        reminderSentAt: Timestamp.fromDate(quando),
      },
    });
    for (const uid of inscritos) {
      marcacoes.push({
        ref: tenantRef
          .collection('sessionOccurrences')
          .doc(id)
          .collection('bookings')
          .doc(uid),
        data: {
          memberId: uid,
          status: 'booked',
          source: 'self',
          isExtra: false,
          serviceId: SERVICO,
          startAt: Timestamp.fromDate(quando),
        },
      });
      presencas.push({
        ref: tenantRef
          .collection('sessionOccurrences')
          .doc(id)
          .collection('attendance')
          .doc(uid),
        data: {
          memberId: uid,
          // Uma em cada dez falta — o painel de retenção precisa de
          // faltas para ter o que contar.
          status: Math.random() < 0.1 ? 'no_show' : 'attended',
          recordedBy: 'instrutor_0',
          recordedAt: Timestamp.fromDate(quando),
        },
      });
    }
  }
}

await cronometrar(
  'seed',
  `${aulasPassadas.length} aulas passadas, ${marcacoes.length} marcações, ` +
    `${presencas.length} presenças`,
  async () => {
    await escreverEmLotes(aulasPassadas);
    await escreverEmLotes(marcacoes);
    await escreverEmLotes(presencas);
  },
);

// Contas de Auth só para quem vai marcar no teste de concorrência.
const CONCORRENTES = Number(arg('concorrentes', '30'));
await cronometrar('seed', `${CONCORRENTES} contas de Auth`, async () => {
  await Promise.all(
    membros.slice(0, CONCORRENTES).map((uid) =>
      adminAuth
        .createUser({ uid, email: `${uid}@carga.test`, password: 'Teste1234' })
        .catch(() => undefined),
    ),
  );
  await adminAuth
    .createUser({
      uid: 'carga_gestor',
      email: 'gestor@carga.test',
      password: 'Teste1234',
    })
    .catch(() => undefined);
});

// ---------------------------------------------------------------------
// Chamar as funções como um utilizador autenticado, sem SDK cliente
// ---------------------------------------------------------------------
//
// O SDK cliente do Firebase não está neste pacote, e acrescentá-lo por
// causa disto seria trazer megabytes para falar com quatro endpoints. O
// protocolo das callables é simples: um POST com o ID token no cabeçalho
// e o payload dentro de `{ data: ... }`.
const AUTH = 'http://localhost:9099/identitytoolkit.googleapis.com/v1';
const FUNCS = `http://localhost:5001/${PROJECT_ID}/${REGION}`;

async function idTokenPara(uid, roles) {
  const custom = await adminAuth.createCustomToken(uid, {
    tenantId: TENANT_ID,
    roles,
  });
  const resposta = await fetch(
    `${AUTH}/accounts:signInWithCustomToken?key=demo-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  if (!resposta.ok) throw new Error(`login falhou: ${resposta.status}`);
  return (await resposta.json()).idToken;
}

async function chamar(idToken, nome, dados) {
  const resposta = await fetch(`${FUNCS}/${nome}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data: dados ?? {} }),
  });
  const corpo = await resposta.json();
  if (!resposta.ok || corpo.error) {
    throw new Error(corpo.error?.message ?? `HTTP ${resposta.status}`);
  }
  return corpo.result;
}

const gestorToken = await idTokenPara('carga_gestor', ['manager']);

console.log('\nMedições\n');

// ---------------------------------------------------------------------
// 2. O cron diário
// ---------------------------------------------------------------------
const resumo = await cronometrar(
  'cron',
  `gerar 8 semanas a partir de ${N_SERIES} séries`,
  async () =>
    await chamar(gestorToken, 'generateRecurringOccurrencesNow'),
);
console.log(
  `         └─ ${resumo.occurrencesCreated} aulas criadas, ` +
    `${resumo.publicScheduleEntries} na vitrina`,
);

// ---------------------------------------------------------------------
// 3. Trinta pessoas a marcar a MESMA aula
// ---------------------------------------------------------------------
const futuras = await tenantRef
  .collection('sessionOccurrences')
  .where('startAt', '>=', Timestamp.now())
  .orderBy('startAt')
  .limit(1)
  .get();
const alvo = futuras.docs[0];
const capacidade = alvo.get('capacity');

// Os tokens são obtidos ANTES do cronómetro: o que se quer medir é a
// concorrência das marcações, não o tempo de autenticar trinta pessoas.
const tokens = await Promise.all(
  membros.slice(0, CONCORRENTES).map((uid) => idTokenPara(uid, ['member'])),
);

const resultados = await cronometrar(
  'concorrência',
  `${CONCORRENTES} marcações simultâneas numa aula de ${capacidade} lugares`,
  async () =>
    Promise.allSettled(
      tokens.map((token, i) =>
        chamar(token, 'createBooking', {
          occurrenceId: alvo.id,
          memberId: membros[i],
        }),
      ),
    ),
);
const aceites = resultados.filter((r) => r.status === 'fulfilled').length;
const contador = (await alvo.ref.get()).get('activeBookingCount');
const reais = (
  await alvo.ref.collection('bookings').where('status', '==', 'booked').get()
).size;
// O certo é o MENOR entre quem tentou e quantos lugares há — com cinco
// pessoas a disputar doze lugares, cinco aceites é o resultado correto.
// A primeira versão desta linha comparava com a lotação e chamava
// "incoerente" a uma corrida perfeita.
const esperado = Math.min(CONCORRENTES, capacidade);
console.log(
  `         └─ ${aceites} aceites (esperado ${esperado}), ` +
    `contador=${contador}, marcações reais=${reais}` +
    (aceites === esperado && contador === reais && reais === aceites
      ? '  ✓ a lotação aguentou'
      : '  ✗ INCOERENTE'),
);

// ---------------------------------------------------------------------
// 4. Painel de retenção — "a função mais cara do projeto"
// ---------------------------------------------------------------------
const retencao = await cronometrar(
  'retenção',
  `painel sobre ${aulasPassadas.length} aulas e ${presencas.length} presenças`,
  async () =>
    await chamar(gestorToken, 'getRetentionOverview', { windowDays: 30 }),
);
console.log(
  `         └─ ${retencao.occupancy.sessions} sessões na janela, ` +
    `${retencao.atRisk.length} em risco`,
);

// ---------------------------------------------------------------------
// 5. Lembretes
// ---------------------------------------------------------------------
const lembretes = await cronometrar('lembretes', 'uma passagem', async () =>
  await chamar(gestorToken, 'sendSessionRemindersNow'),
);
console.log(
  `         └─ ${lembretes.occurrences} aulas processadas, ` +
    `${lembretes.notified} avisos`,
);

// ---------------------------------------------------------------------
// 6. O que a app lê ao abrir
// ---------------------------------------------------------------------
await cronometrar('app · Gestor', 'lista de membros', async () => {
  const s = await tenantRef.collection('members').get();
  return s.size;
});
await cronometrar('app · Gestor', 'contagem de membros ativos', async () => {
  const s = await tenantRef
    .collection('members')
    .where('status', '==', 'active')
    .count()
    .get();
  return s.data().count;
});
await cronometrar('app · Aluno', 'aulas das próximas 2 semanas', async () => {
  const s = await tenantRef
    .collection('sessionOccurrences')
    .where('serviceId', '==', SERVICO)
    .where('startAt', '>=', Timestamp.now())
    .where(
      'startAt',
      '<=',
      Timestamp.fromDate(new Date(Date.now() + 14 * 86_400_000)),
    )
    .get();
  return s.size;
});
await cronometrar('app · Aluno', 'as minhas marcações', async () => {
  const s = await db
    .collectionGroup('bookings')
    .where('memberId', '==', membros[0])
    .where('status', '==', 'booked')
    .get();
  return s.size;
});

// ---------------------------------------------------------------------
// Resumo
// ---------------------------------------------------------------------
console.log('\n' + '─'.repeat(66));
const lentas = medicoes
  .filter((m) => !m.nome.startsWith('seed') && m.ms > 1000)
  .sort((a, b) => b.ms - a.ms);
if (lentas.length === 0) {
  console.log('Nada acima de 1 segundo.');
} else {
  console.log('Acima de 1 segundo:');
  for (const m of lentas) {
    console.log(`  ${m.ms.toFixed(0).padStart(6)} ms  ${m.nome} — ${m.detalhe}`);
  }
}
console.log(
  '\nNota: o emulador corre num processo só e é mais lento do que a\n' +
    'produção em latência, mas NÃO modela a rede. Os números servem para\n' +
    'comparar operações entre si e apanhar o que cresce mal, não para\n' +
    'prever o tempo que um telemóvel vai sentir.',
);

await db.recursiveDelete(tenantRef);
process.exit(0);
