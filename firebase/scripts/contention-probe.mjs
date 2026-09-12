// Contenção medida DIRETAMENTE no Firestore, sem passar pelas funções.
//
// O emulador de funções serializa invocações e tem um teto de
// concorrência próprio (306 s, idêntico para 10 e para 30 — é um limite
// a ser atingido, não carga). Isso é ferramenta, não produto. Esta
// sonda replica a transação de `runBookingTransaction` contra o
// emulador do Firestore e varia só o `maxAttempts`, para responder à
// única pergunta que interessa: com quantas tentativas é que trinta
// pessoas a marcar a mesma aula passam todas?
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
const app = initializeApp({ projectId: 'demo-gym-saas-dev' });
const db = getFirestore(app);

const CONCORRENTES = Number(process.argv[2] ?? 30);
const CAPACIDADE = 12;
const TENTATIVAS = (process.argv[3] ?? '5,10,15').split(',').map(Number);
const RONDAS = Number(process.argv[4] ?? 3);

async function corrida(maxAttempts, etiqueta) {
  const aula = db.doc(`sondas/${etiqueta}`);
  await db.recursiveDelete(aula);
  await aula.set({ capacity: CAPACIDADE, activeBookingCount: 0 });

  const inicio = Date.now();
  const r = await Promise.allSettled(
    Array.from({ length: CONCORRENTES }, (_, i) =>
      db.runTransaction(
        async (tx) => {
          const doc = await tx.get(aula);
          const contagem = doc.get('activeBookingCount');
          if (contagem >= doc.get('capacity')) throw new Error('cheia');
          tx.set(aula.collection('bookings').doc(`m${i}`), {
            memberId: `m${i}`,
            status: 'booked',
          });
          tx.update(aula, { activeBookingCount: contagem + 1 });
        },
        { maxAttempts },
      ),
    ),
  );
  const ms = Date.now() - inicio;

  const aceites = r.filter((x) => x.status === 'fulfilled').length;
  // Uma recusa por lotação é a resposta CERTA e imediata. Uma recusa
  // por esgotar tentativas é uma pessoa mandada embora de uma aula com
  // lugares — é essa, e só essa, que este teste procura.
  const porLotacao = r.filter(
    (x) => x.status === 'rejected' && /cheia/.test(String(x.reason?.message)),
  ).length;
  const perdidos = CONCORRENTES - aceites - porLotacao;
  const esperado = Math.min(CONCORRENTES, CAPACIDADE);
  const contador = (await aula.get()).get('activeBookingCount');
  const reais = (await aula.collection('bookings').get()).size;
  const coerente = aceites === esperado && contador === reais && reais === aceites;

  console.log(
    `  maxAttempts=${String(maxAttempts).padStart(2)}  ` +
      `${String(ms).padStart(6)} ms  ${aceites}/${esperado} aceites  ` +
      `perdidos-por-tentativas=${perdidos}  ` +
      (coerente && perdidos === 0 ? '✓' : '✗'),
  );
  return perdidos;
}

console.log(
  `\n${CONCORRENTES} transações simultâneas num contador de ${CAPACIDADE} lugares\n`,
);
for (const t of TENTATIVAS) {
  let falhas = 0;
  for (let ronda = 0; ronda < RONDAS; ronda++) {
    falhas += await corrida(t, `t${t}_r${ronda}`);
  }
  console.log(
    `  └─ ${RONDAS} rondas: ${falhas === 0 ? 'nunca perdeu ninguém' : `${falhas} perdidos no total`}\n`,
  );
}
process.exit(0);
