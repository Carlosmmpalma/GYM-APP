// Seed de desenvolvimento — corre SÓ contra o Firebase Emulator Suite.
//
// Cria:
//   1. O tenant real "NXT Performance Studio" + o primeiro Gestor (Leo).
//   2. Um tenant fantasma, só para testes manuais de isolamento
//      (guia-desenvolvimento.md, Fase 1: "Cria um segundo 'tenant
//      fantasma' só para os testes de isolamento tentarem invadir").
//   3. Uma Service ("Aula de Grupo") + uma SessionOccurrence de teste
//      com capacidade 2, para testar o ecrã "Marcar treino" (Fase 2).
//
// Usa o Admin SDK, que ignora Security Rules — por isso funciona mesmo
// antes de existir nenhuma regra de isolamento escrita.
//
// Corre com (depois de `npm install` nesta pasta, e com
// `firebase emulators:start` a correr noutro terminal):
//   npm run seed

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

// Tem de corresponder a:
//   lib/infrastructure/config/firebase_options_development.dart (projectId)
//   .firebaserc.example (projects.development)
const PROJECT_ID = 'demo-gym-saas-dev';

const REAL_TENANT_ID = 'nxt_performance_studio';
const GHOST_TENANT_ID = 'ghost_gym_isolation_test';

initializeApp({ projectId: PROJECT_ID });
const auth = getAuth();
const firestore = getFirestore();

function buildSyntheticEmail(tenantId, memberNumber) {
  return `member-${memberNumber}@${tenantId}.gymsaas.internal`.toLowerCase();
}

async function upsertTenant(tenantId, name) {
  await firestore.collection('tenants').doc(tenantId).set(
    {
      name,
      timezone: 'Europe/Lisbon',
      status: 'active',
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`✓ tenant "${tenantId}" (${name})`);
}

async function createAuthUserIfMissing({ email, password, displayName }) {
  try {
    const existing = await auth.getUserByEmail(email);
    console.log(`  já existe: ${email} (uid=${existing.uid}) — a saltar criação`);
    return existing;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  return auth.createUser({ email, password, displayName });
}

async function seedManager() {
  const email = 'leo@nxtperformancestudio.pt';
  const password = 'DevPass123!';

  const user = await createAuthUserIfMissing({
    email,
    password,
    displayName: 'Leo Gil',
  });

  await auth.setCustomUserClaims(user.uid, {
    tenantId: REAL_TENANT_ID,
    roles: ['manager'],
  });

  await firestore
    .collection('tenants')
    .doc(REAL_TENANT_ID)
    .collection('staff')
    .doc(user.uid)
    .set(
      {
        userId: user.uid,
        name: 'Leo Gil',
        email,
        roles: ['manager'],
        status: 'active',
        passwordTemporaria: false, // conta de dev — já "trocada"
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  console.log(`✓ gestor "${email}" / password "${password}" (uid=${user.uid})`);
}

/**
 * Fase 11 — não existia NENHUMA conta de instrutor no seed. O shell do
 * Instrutor (calendário, alunos, biblioteca, presenças) só se conseguia
 * testar entrando como Gestor, que vê outra coisa.
 *
 * Staff autentica-se com email real, ao contrário dos membros (email
 * sintético a partir do nº de sócio) — ver `createStaff.ts`.
 */
async function seedInstructor() {
  const email = 'ana@nxtperformancestudio.pt';
  const password = 'InstructorPass123!';

  const user = await createAuthUserIfMissing({
    email,
    password,
    displayName: 'Ana Marques',
  });

  await auth.setCustomUserClaims(user.uid, {
    tenantId: REAL_TENANT_ID,
    roles: ['instructor'],
  });

  await firestore
    .collection('tenants')
    .doc(REAL_TENANT_ID)
    .collection('staff')
    .doc(user.uid)
    .set(
      {
        userId: user.uid,
        name: 'Ana Marques',
        email,
        roles: ['instructor'],
        status: 'active',
        passwordTemporaria: false, // conta de dev — já "trocada"
        // Fase 11 — os serviços que a Ana pode lecionar. Sem isto, o
        // atalho "Criar aula" nem aparece no dashboard dela: as
        // Security Rules recusam a criação, e um atalho que leva a uma
        // recusa é pior do que atalho nenhum.
        serviceIds: ['group_classes_test'],
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  console.log(`✓ instrutor "${email}" / password "${password}" (uid=${user.uid})`);
  return user;
}

async function seedMember({ tenantId, memberNumber, name, password }) {
  const email = buildSyntheticEmail(tenantId, memberNumber);

  const user = await createAuthUserIfMissing({ email, password, displayName: name });

  await auth.setCustomUserClaims(user.uid, {
    tenantId,
    roles: ['member'],
  });

  await firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('members')
    .doc(user.uid)
    .set(
      {
        userId: user.uid,
        memberNumber,
        name,
        status: 'active',
        passwordTemporaria: false,
        // Fase 11 (RGPD) — conta de dev já com consentimento dado, senão
        // cada arranque parava no ecrã de consentimento antes de se
        // conseguir testar o resto. Para VER esse ecrã, cria um membro
        // novo pela app (nasce sem consentimento) ou apaga este campo
        // na UI do emulador.
        consent: {
          privacyPolicyVersion: 1,
          acceptedAt: FieldValue.serverTimestamp(),
          healthDataGranted: true,
          healthDataUpdatedAt: FieldValue.serverTimestamp(),
        },
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  console.log(
    `✓ membro "${tenantId}" nº "${memberNumber}" / password "${password}" (uid=${user.uid})`,
  );
  return user;
}

async function seedServiceAndOccurrence(tenantId, instructorId) {
  const serviceId = 'group_classes_test';
  const serviceRef = firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('services')
    .doc(serviceId);

  await serviceRef.set(
    { name: 'Aula de Grupo', active: true, createdAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  console.log(`✓ service "${serviceId}" (Aula de Grupo)`);

  await seedOccurrence(tenantId, serviceId, 'occurrence_test_1', 1, 18, instructorId);
  // Fase 4 — uma segunda ocorrência na MESMA semana ISO (2 dias depois,
  // quase sempre a mesma semana segunda-domingo, exceto se
  // "occurrence_test_1" calhar num domingo — aceitável para dados de
  // seed): sem isto não dava para testar o bloqueio de limite semanal
  // (o plano de teste agora dá só 1x/semana — ver seedPlanAndSubscription)
  // com só UMA sessão disponível para marcar.
  await seedOccurrence(tenantId, serviceId, 'occurrence_test_2', 2, 19, instructorId);
}

async function seedOccurrence(
  tenantId,
  serviceId,
  occurrenceId,
  daysFromNow,
  hour,
  instructorId = null,
) {
  const occurrenceRef = firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('sessionOccurrences')
    .doc(occurrenceId);

  const existing = await occurrenceRef.get();
  if (existing.exists) {
    console.log(
      `  já existe: sessionOccurrences/${occurrenceId} — a saltar ` +
        `(para não sobrescrever activeBookingCount de bookings reais já feitos)`,
    );
    return;
  }

  const startAt = new Date();
  startAt.setDate(startAt.getDate() + daysFromNow);
  startAt.setHours(hour, 0, 0, 0);
  const endAt = new Date(startAt.getTime() + 60 * 60 * 1000);

  await occurrenceRef.set({
    serviceId,
    // Fase 11 — atribuído à instrutora semeada, senão o calendário do
    // Instrutor abre vazio e não há nada para testar (presenças,
    // remarcar, reduzir vagas).
    instructorId,
    startAt,
    endAt,
    capacity: 2,
    status: 'scheduled',
    activeBookingCount: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(
    `✓ sessionOccurrence "${occurrenceId}" — ${startAt.toISOString()}, capacidade 2`,
  );
}

// Fase 3 — um Plan de teste que dá acesso à Service semeada acima, e
// uma Subscription ativa para a Rita. Sem isto, a query de
// elegibilidade (`isEligibleForService`, Fase 3) bloqueava sempre o
// booking manual em Chrome, porque nenhum membro tinha nenhuma
// subscription. Escrita direta via Admin SDK (ignora Security Rules e
// não passa pela Cloud Function `createSubscription` — aceitável aqui
// porque é só um documento fixo, sem nenhuma outra subscription para
// entrar em conflito).
async function seedPlanAndSubscription(tenantId, memberId, serviceId) {
  const planId = 'plan_test_standard';
  const planRef = firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('plans')
    .doc(planId);

  await planRef.set(
    {
      name: 'Standard (teste)',
      description: 'Plano de teste criado pelo seed script.',
      currentPrice: 39.9,
      currency: 'EUR',
      active: true,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  // Fase 4 — limited (1x/semana), não unlimited como até à Fase 3: sem
  // isto não dava para testar o bloqueio de limite semanal sem editar
  // manualmente o Plan em "Gestão → Planos" primeiro. Este `.set()`
  // (sem `existing` check) corre sempre, mesmo com o emulador já
  // semeado antes — por isso um `npm run seed` a repetir já atualiza a
  // regra de um ambiente antigo.
  await planRef.collection('services').doc(serviceId).set({
    serviceId,
    enabled: true,
    usage: { type: 'limited', limit: 1, period: 'week' },
  });
  console.log(
    `✓ plan "${planId}" (Standard) — inclui service "${serviceId}" (1x/semana)`,
  );

  const subscriptionRef = firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('subscriptions')
    .doc('subscription_test_rita');

  const existing = await subscriptionRef.get();
  if (existing.exists) {
    console.log('  já existe: subscriptions/subscription_test_rita — a saltar');
    return;
  }

  await subscriptionRef.set({
    memberId,
    planId,
    status: 'active',
    startDate: FieldValue.serverTimestamp(),
    agreedPrice: 39.9,
    currency: 'EUR',
    activeServiceIds: [serviceId],
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(`✓ subscription "subscription_test_rita" — Rita (${memberId}) → ${planId}`);
}

// Fase 5 — uma série ativa de exemplo ("Hyrox — Segundas 18:00"), com
// a Rita já pré-atribuída (modelo híbrido, UC17/UC19 fechado): sem
// isto, "Gestão → Aulas/Horários" ficaria vazio depois do seed, e não
// havia forma de ver a auto-atribuição a funcionar sem criar tudo à
// mão na app primeiro. Só um membro pré-atribuído (o único semeado até
// agora) — a série gera as próprias ocorrências quando chamares
// "Gerar agora" (não faz nada sozinha até lá).
async function seedRecurringSeries(tenantId, serviceId, memberId, instructorId = null) {
  const seriesId = 'series_test_hyrox_mon';
  const seriesRef = firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('sessionSeries')
    .doc(seriesId);

  const existing = await seriesRef.get();
  if (existing.exists) {
    console.log(`  já existe: sessionSeries/${seriesId} — a saltar`);
    return;
  }

  await seriesRef.set({
    serviceId,
    instructorId,
    dayOfWeek: 1, // segunda-feira (DateTime.monday, mesma convenção do Dart)
    startTime: '18:00',
    durationMinutes: 60,
    capacity: 6,
    startDate: new Date(),
    preAssignedMemberIds: [memberId],
    status: 'active',
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(
    `✓ sessionSeries "${seriesId}" — Segundas 18:00, capacidade 6, Rita pré-atribuída ` +
      '(sem ocorrências ainda — usa "Gerar agora" na app ou espera pelo cron diário)',
  );
}

/**
 * Fase 11 — o treino livre precisa de um serviço, como qualquer
 * marcação: é o que o liga ao plano do aluno e ao limite semanal. Mas é
 * SEMPRE o mesmo, por isso é uma definição do estúdio e não uma escolha
 * repetida a cada grelha e a cada bloco.
 */
async function seedFreeTraining(tenantId) {
  const serviceId = 'free_training';
  await firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('services')
    .doc(serviceId)
    .set(
      { name: 'Treino Livre', active: true, createdAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

  await firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('config')
    .doc('bookingPolicy')
    .set({ freeTrainingServiceId: serviceId }, { merge: true });

  console.log(`✓ serviço "${serviceId}" (Treino Livre) + definição do estúdio`);
}

async function main() {
  console.log(`A semear contra o emulador (projectId=${PROJECT_ID})...\n`);

  await upsertTenant(REAL_TENANT_ID, 'NXT Performance Studio');
  await seedManager();
  const ana = await seedInstructor();
  const rita = await seedMember({
    tenantId: REAL_TENANT_ID,
    memberNumber: '000001',
    name: 'Rita Ferreira',
    password: 'MemberPass123!',
  });
  await seedServiceAndOccurrence(REAL_TENANT_ID, ana.uid);
  await seedFreeTraining(REAL_TENANT_ID);
  await seedPlanAndSubscription(REAL_TENANT_ID, rita.uid, 'group_classes_test');
  // Fase 11 — o plano de teste passa a incluir também o treino livre.
  // Sem isto, a aluna semeada entrava e via "o teu plano não inclui
  // treino livre", que é verdade mas não ajuda a testar o fluxo.
  await firestore
    .collection('tenants')
    .doc(REAL_TENANT_ID)
    .collection('plans')
    .doc('plan_test_standard')
    .collection('services')
    .doc('free_training')
    .set({ enabled: true, usage: { type: 'unlimited' } }, { merge: true });
  await firestore
    .collection('tenants')
    .doc(REAL_TENANT_ID)
    .collection('subscriptions')
    .doc('subscription_test_rita')
    .set(
      { activeServiceIds: ['group_classes_test', 'free_training'] },
      { merge: true },
    );
  console.log('✓ plano de teste inclui treino livre (e a subscrição também)');

  await seedRecurringSeries(REAL_TENANT_ID, 'group_classes_test', rita.uid, ana.uid);

  console.log();
  await upsertTenant(GHOST_TENANT_ID, 'Ghost Gym (só para testes de isolamento)');
  await seedMember({
    tenantId: GHOST_TENANT_ID,
    memberNumber: '000001',
    name: 'Fantasma de Teste',
    password: 'GhostPass123!',
  });

  console.log(
    '\nPronto:\n' +
      '  - Login na app (UC01) com nº de sócio "000001" / password ' +
      '"MemberPass123!" testa o tenant real ponta a ponta.\n' +
      '  - O tenant fantasma tem o MESMO nº de sócio ("000001") mas uma ' +
      'password diferente — confirma na UI do emulador ' +
      '(http://localhost:4000/firestore) que são documentos completamente ' +
      'separados, apesar do número igual (o isolamento é por tenantId, não ' +
      'pelo número em si).\n' +
      '  - No separador "Marcar", a Rita já tem DUAS sessões de "Aula de ' +
      'Grupo" esta semana (amanhã às 18:00 e depois de amanhã às 19:00, ' +
      'cada uma com 2 vagas) para testar o booking (Fase 2).\n' +
      '  - A Rita já tem uma subscription ativa ao plano "Standard (teste)", ' +
      'que dá acesso a "Aula de Grupo" — o booking não fica bloqueado pela ' +
      'verificação de elegibilidade (Fase 3). Para testar o bloqueio de ' +
      'elegibilidade, cria outro membro sem subscription e tenta marcar.\n' +
      '  - Fase 4: o plano "Standard (teste)" dá agora só 1x/semana a ' +
      '"Aula de Grupo" (era ilimitado até à Fase 3). Marca a PRIMEIRA ' +
      'sessão com a Rita — deve resultar em sucesso e a barra no topo do ' +
      'ecrã "Marcar" deve passar a mostrar "1/1 sessões de Aula de ' +
      'Grupo". Tenta marcar a SEGUNDA sessão — deve ser bloqueado com ' +
      '"Já atingiste o limite semanal deste serviço (1/1)". Cancela a ' +
      'primeira marcação em "Minhas marcações" (sem antecedência mínima ' +
      'configurada em "Gestão → Definições", o cancelamento devolve ' +
      'sempre a utilização) e confirma que a barra volta a "0/1" e a ' +
      'segunda sessão volta a ficar marcável.\n' +
      '  - Fase 5: existe uma série "Hyrox — Segundas 18:00" (Gestão → ' +
      'Aulas/Horários), com a Rita já pré-atribuída, mas AINDA SEM ' +
      'ocorrências geradas. Abre-a e usa "Gerar agora" — devem aparecer ' +
      'várias segundas-feiras futuras, cada uma já com a Rita marcada ' +
      'automaticamente (confirma em "Minhas marcações" dela).',
  );
}

main().catch((err) => {
  console.error('Falhou:', err);
  process.exitCode = 1;
});
