// A conta para quem revê a app na App Store / Play Store.
//
// ## Porque é um script próprio
//
// Já existe o `create-test-users.mjs`, e não serve: as contas que ele
// cria estão **vazias**. Um reviewer que entre e veja "sem marcações,
// sem plano de treino, sem avaliações" fica exatamente onde estava — a
// olhar para uma app que não consegue avaliar. E há um risco concreto:
// essas contas têm `isTestAccount: true` e são apagadas em bloco por
// `create-test-users.mjs --delete`. Apagar a conta de demonstração a
// meio de uma revisão é rejeição garantida, e é o tipo de coisa que se
// faz sem pensar.
//
// Por isso esta conta é marcada com `isReviewAccount: true` e **não**
// com `isTestAccount`. O `--delete` das contas de teste não lhe toca.
//
// ## O que cria
//
// Um aluno com o estúdio já andado: plano contratado, aulas marcadas
// nas próximas semanas, um plano de treino com três treinos, uma
// avaliação física e a mensalidade do mês paga. É o suficiente para
// alguém abrir a app e perceber o que ela faz em trinta segundos.
//
// Pressupõe que o catálogo já existe (`seed-content.mjs`) e que há
// séries a gerar ocorrências. Diz o que falta em vez de rebentar.
//
//   node seed-review-account.mjs --project=gym-sas \
//     --tenant=nxt_performance_studio --yes
//
// Sem `--yes` diz o que ia fazer e não faz nada. Correr duas vezes é
// seguro: repõe a password e volta a pôr os dados no sítio.

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectId = arg('project');
const tenantId = arg('tenant');
// Fora da gama dos sócios reais (000001+) e da das contas de teste
// (900001+): 999000 é reconhecível de relance e não colide com nada.
const memberNumber = arg('number', '999000');
const password = arg('password', 'AppReview2026!');
const confirmed = process.argv.includes('--yes');

if (!projectId || !tenantId) {
  console.error('Faltam argumentos: --project e --tenant.');
  process.exit(1);
}

/// Mesmo `toDomainLabel` do `lib/core/config/login_identifier.dart` e do
/// `loginIdentifier.ts`. O underscore num domínio de email é recusado
/// pelo Firebase Auth em produção (e aceite pelo emulador) — foi assim
/// que o lançamento partiu da primeira vez.
function toDomainLabel(value) {
  const collapsed = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return collapsed === '' ? 'tenant' : collapsed;
}

const email = `member-${memberNumber}@${toDomainLabel(tenantId)}.gymsaas.internal`;
const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

if (!confirmed) {
  console.log(
    `Ia criar a conta de revisão nº ${memberNumber} em "${projectId}" ` +
      `(tenant "${tenantId}")${usingEmulator ? ' [EMULADOR]' : ' [PROJETO REAL]'}.`,
  );
  console.log('Sem --yes: nada foi escrito.');
  process.exit(0);
}

initializeApp({ projectId });
const auth = getAuth();
const firestore = getFirestore();
const tenantRef = firestore.collection('tenants').doc(tenantId);

// ---------------------------------------------------------------------
// 1. A conta.
// ---------------------------------------------------------------------
let user;
try {
  user = await auth.getUserByEmail(email);
  await auth.updateUser(user.uid, { password, displayName: 'Conta de Revisão' });
  console.log('· a conta já existia — password reposta');
} catch {
  user = await auth.createUser({
    email,
    password,
    displayName: 'Conta de Revisão',
  });
  console.log('✓ conta de Auth criada');
}
await auth.setCustomUserClaims(user.uid, { tenantId, roles: ['member'] });

const memberRef = tenantRef.collection('members').doc(user.uid);
await memberRef.set(
  {
    memberNumber,
    name: 'Conta de Revisão',
    status: 'active',
    phone: '+351 210 000 000',
    email: 'appreview@exemplo.test',
    // Não é `isTestAccount`: ver o cabeçalho. O `--delete` das contas de
    // teste não pode levar esta à frente a meio de uma revisão.
    isReviewAccount: true,
    passwordTemporaria: false,
    // Consentimento já registado: o ecrã de consentimento é uma parede
    // legítima, mas o objetivo aqui é que quem abre a app caia direto no
    // produto. A política continua a um toque em "Os meus dados".
    consent: {
      privacyPolicyVersion: 1,
      acceptedAt: FieldValue.serverTimestamp(),
      healthDataGranted: true,
      healthDataUpdatedAt: FieldValue.serverTimestamp(),
    },
  },
  { merge: true },
);
console.log(`✓ membro nº ${memberNumber}`);

// ---------------------------------------------------------------------
// 2. Um plano contratado — sem isto não pode marcar nada.
// ---------------------------------------------------------------------
const plansSnap = await tenantRef
  .collection('plans')
  .where('active', '==', true)
  .get();

if (plansSnap.empty) {
  console.error(
    '✗ Não há planos ativos neste tenant. Corre o `seed-content.mjs` primeiro.',
  );
  process.exit(1);
}

// Os serviços de um plano vivem numa SUBCOLEÇÃO (`plans/{id}/services`)
// e não num array no documento — ver `seed-content.mjs`. Sem isto a
// escolha do plano era feita sobre um campo que não existe, e saía
// sempre o primeiro da lista.
const planosComServicos = await Promise.all(
  plansSnap.docs.map(async (doc) => {
    const servicos = await doc.ref
      .collection('services')
      .where('enabled', '==', true)
      .get();
    return { doc, serviceIds: servicos.docs.map((s) => s.id) };
  }),
);

// O plano com mais serviços: é o que dá acesso a mais coisas para ver.
const escolhido = planosComServicos.sort(
  (a, b) => b.serviceIds.length - a.serviceIds.length,
)[0];
const plan = escolhido.doc;
const serviceIds = escolhido.serviceIds;

if (serviceIds.length === 0) {
  console.warn('! O plano escolhido não tem serviços — nada para marcar.');
}

await tenantRef
  .collection('subscriptions')
  .doc(`subscription_review_${memberNumber}`)
  .set(
    {
      memberId: user.uid,
      planId: plan.id,
      status: 'active',
      startDate: FieldValue.serverTimestamp(),
      agreedPrice: plan.get('currentPrice') ?? 0,
      activeServiceIds: serviceIds,
    },
    { merge: true },
  );
console.log(
  `✓ plano "${plan.get('name')}" contratado — ${serviceIds.length} serviço(s)`,
);

// ---------------------------------------------------------------------
// 3. Aulas marcadas — o ecrã "Próxima marcação" tem de ter o que dizer.
// ---------------------------------------------------------------------
const now = new Date();
const upcoming = await tenantRef
  .collection('sessionOccurrences')
  .where('startAt', '>=', Timestamp.fromDate(now))
  .orderBy('startAt')
  .limit(30)
  .get();

const bookable = upcoming.docs.filter(
  (doc) =>
    doc.get('status') === 'scheduled' && serviceIds.includes(doc.get('serviceId')),
);

if (bookable.length === 0) {
  console.warn(
    '! Sem aulas futuras para marcar. Corre `generateRecurringOccurrencesNow` ' +
      'na app (Gestão) ou espera pelo cron, e volta a correr isto.',
  );
} else {
  // Três chegam: uma para "próxima marcação", as outras para a lista ter
  // corpo. Escrita direta e não `createBooking`, de propósito — este
  // script corre com o Admin SDK e não tem sessão de cliente; o contador
  // é acertado à mão logo a seguir.
  const escolhidas = bookable.slice(0, 3);
  for (const occurrence of escolhidas) {
    await occurrence.ref.collection('bookings').doc(user.uid).set(
      {
        memberId: user.uid,
        status: 'booked',
        source: 'manager',
        isExtra: false,
        serviceId: occurrence.get('serviceId'),
        startAt: occurrence.get('startAt'),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    const ativos = await occurrence.ref
      .collection('bookings')
      .where('status', '==', 'booked')
      .count()
      .get();
    await occurrence.ref.update({ activeBookingCount: ativos.data().count });
  }
  console.log(`✓ ${escolhidas.length} aula(s) marcada(s)`);
}

// ---------------------------------------------------------------------
// 4. Plano de treino — é o coração da app e não pode estar vazio.
// ---------------------------------------------------------------------
const exercisesSnap = await tenantRef.collection('exercises').limit(12).get();

if (exercisesSnap.empty) {
  console.warn(
    '! Sem exercícios na biblioteca. Corre ' +
      '`seed-content.mjs --only=exercicios` e volta a correr isto.',
  );
} else {
  const exercicios = exercisesSnap.docs;
  const treinos = [
    { id: 'review_treino_a', name: 'Treino A — Empurrar', notes: 'Peito, ombro e tríceps.' },
    { id: 'review_treino_b', name: 'Treino B — Puxar', notes: 'Costas e bíceps.' },
    { id: 'review_treino_c', name: 'Treino C — Pernas', notes: 'Membros inferiores.' },
  ];

  const batch = firestore.batch();
  treinos.forEach((treino, indice) => {
    batch.set(
      memberRef.collection('workouts').doc(treino.id),
      {
        name: treino.name,
        notes: treino.notes,
        position: indice,
        active: true,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // Quatro exercícios por treino, tirados da biblioteca real.
    for (let i = 0; i < 4; i++) {
      const exercicio = exercicios[(indice * 4 + i) % exercicios.length];
      batch.set(
        memberRef.collection('planEntries').doc(`${treino.id}_${i}`),
        {
          exerciseId: exercicio.id,
          sets: 4,
          reps: '10',
          currentLoad: 20 + i * 10,
          workoutId: treino.id,
          position: i,
          restSeconds: 90,
          notes: '',
        },
        { merge: true },
      );
    }
  });
  await batch.commit();
  console.log('✓ plano de treino com 3 treinos');
}

// ---------------------------------------------------------------------
// 5. Uma avaliação física e a mensalidade do mês.
// ---------------------------------------------------------------------
await memberRef
  .collection('assessments')
  .doc('review_avaliacao_1')
  .set(
    {
      memberId: user.uid,
      recordedAt: Timestamp.fromDate(
        new Date(now.getTime() - 21 * 86_400_000),
      ),
      recordedBy: 'seed-review-account',
      weightKg: 72.4,
      heightCm: 175,
      bodyFatPercent: 18.2,
      visceralFat: 6,
      restingHeartRate: 62,
      notes: 'Avaliação inicial.',
    },
    { merge: true },
  );

const periodo = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
await memberRef.collection('paymentRecords').doc(periodo).set(
  {
    memberId: user.uid,
    year: now.getFullYear(),
    month: now.getMonth() + 1,
    status: 'paid',
    amount: plan.get('currentPrice') ?? 0,
    changedAt: FieldValue.serverTimestamp(),
    changedBy: 'seed-review-account',
  },
  { merge: true },
);
await memberRef.set(
  { currentPaymentStatus: 'paid', currentPaymentPeriod: periodo },
  { merge: true },
);
console.log('✓ avaliação física e mensalidade do mês');

// ---------------------------------------------------------------------
// O que copiar para as review notes.
// ---------------------------------------------------------------------
console.log(`
─────────────────────────────────────────────────────────────
Para as App Review Information / review notes:

  Nº de sócio: ${memberNumber}
  Password:    ${password}

Texto sugerido:

  This app is the member app for a single gym (${tenantId}).
  Accounts are created by the gym staff when a person signs up in
  person — there is no public sign-up flow inside the app, which is
  why you will not find one. The demo account above is a real member
  account with a plan, bookings, a training programme and an
  assessment already in it.

  Anyone can open the app and see the gym's address, opening hours
  and class timetable without an account; "Já sou membro — entrar"
  leads to the login.

⚠️ Confirma antes de submeter que Gestão › Informação pública está
   preenchida — sobretudo a política de privacidade. A vitrina esconde o
   que falta, por isso um ecrã bonito não prova que lá está.

⚠️ NÃO corras \`create-test-users.mjs --delete\` durante a revisão.
   Esta conta não é apagada por ele (não tem \`isTestAccount\`), mas as
   outras são — e uma app meio vazia é meio caminho para a rejeição.
─────────────────────────────────────────────────────────────`);
