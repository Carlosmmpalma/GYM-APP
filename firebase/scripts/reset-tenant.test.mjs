// Prova o reset-tenant.mjs contra o emulador antes de o apontar a
// produção. Semeia um estúdio com a MESMA forma que o real — documentos
// com subcoleções, staff com `private`, uma coleção a guardar — corre o
// script, e verifica o que ficou.

import { execFileSync } from 'node:child_process';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

const PROJECT = 'demo-reset';
const TENANT = 't_reset';

initializeApp({ projectId: PROJECT });
const db = getFirestore();
const auth = getAuth();
const t = db.collection('tenants').doc(TENANT);

async function semear() {
  await t.set({ name: 'Estúdio de teste', status: 'active' });

  const mgr = await auth.createUser({ uid: 'mgr', email: 'gestor@teste.pt', password: 'Password123!' });
  await auth.setCustomUserClaims(mgr.uid, { tenantId: TENANT, roles: ['manager'] });
  await t.collection('staff').doc('mgr').set({ name: 'Gestor', roles: ['manager'], status: 'active' });
  await t.collection('staff').doc('mgr').collection('private').doc('contacts').set({ phone: '910000000' });

  await auth.createUser({ uid: 'inst', email: 'instrutor@teste.pt', password: 'Password123!' });
  await auth.setCustomUserClaims('inst', { tenantId: TENANT, roles: ['instructor'] });
  await t.collection('staff').doc('inst').set({ name: 'Instrutor', roles: ['instructor'] });
  await t.collection('staff').doc('inst').collection('private').doc('contacts').set({ phone: '920000000' });

  await auth.createUser({ uid: 'm1', email: 'aluno@teste.pt', password: 'Password123!' });
  await auth.setCustomUserClaims('m1', { tenantId: TENANT, roles: ['member'] });
  await t.collection('members').doc('m1').set({ name: 'Aluno', status: 'active' });
  await t.collection('members').doc('m1').collection('assessments').doc('a1').set({ weight: 70 });
  await t.collection('members').doc('m1').collection('paymentRecords').doc('p1').set({ amount: 30 });

  // Uma conta de Auth do estúdio cujo documento já não existe — é o caso
  // que só a varredura por claims apanha.
  await auth.createUser({ uid: 'orfao', email: 'orfao@teste.pt', password: 'Password123!' });
  await auth.setCustomUserClaims('orfao', { tenantId: TENANT, roles: ['member'] });

  // E uma conta de OUTRO estúdio, que não pode ser tocada.
  await auth.createUser({ uid: 'alheio', email: 'alheio@outro.pt', password: 'Password123!' });
  await auth.setCustomUserClaims('alheio', { tenantId: 'outro_tenant', roles: ['manager'] });

  await t.collection('sessionOccurrences').doc('occ1').set({ status: 'scheduled', activeBookingCount: 1 });
  await t.collection('sessionOccurrences').doc('occ1').collection('bookings').doc('m1').set({ status: 'booked' });
  await t.collection('sessionOccurrences').doc('occ1').collection('attendance').doc('m1').set({ status: 'attended' });

  await t.collection('freeTrainingSchedules').doc('w1').set({ weekId: 'w1' });
  await t.collection('freeTrainingSchedules').doc('w1').collection('slots').doc('s1').set({ capacity: 2 });

  await t.collection('config').doc('bookingPolicy').set({ freeTrainingServiceId: 'svc' });
  await t.collection('services').doc('svc').set({ name: 'Aulas' });
  await t.collection('plans').doc('p').set({ name: 'Plano' });
  await t.collection('subscriptions').doc('s').set({ memberId: 'm1' });
  await t.collection('usage').doc('m1_svc_2026-W01').set({ used: 1 });
  await t.collection('public').doc('schedule').set({ entries: [] });

  // A guardar.
  await t.collection('exercises').doc('ex_1').set({ name: 'Agachamento' });
  await t.collection('exerciseCategories').doc('c1').set({ name: 'Pernas' });

  await db.collection('_rateLimits').doc('m1__createBooking').set({ count: 3 });
}

const falhas = [];
function verificar(descricao, condicao) {
  if (condicao) console.log(`  ok    ${descricao}`);
  else {
    console.log(`  FALHA ${descricao}`);
    falhas.push(descricao);
  }
}

async function existe(ref) {
  return (await ref.get()).exists;
}

async function contar(col) {
  return (await col.listDocuments()).length;
}

await semear();
console.log('Semeado.\n');

console.log(
  execFileSync(
    process.execPath,
    [
      'C:/_dev/Apps/Gyms/app/firebase/scripts/reset-tenant.mjs',
      `--project=${PROJECT}`,
      `--tenant=${TENANT}`,
      '--keep-manager=gestor@teste.pt',
      '--keep=exercises,exerciseCategories',
      '--yes',
    ],
    { encoding: 'utf8', env: process.env },
  ),
);

console.log('Verificação:');

// O que TEM de ficar.
verificar('o documento do estúdio ficou', await existe(t));
verificar('o Gestor ficou em staff', await existe(t.collection('staff').doc('mgr')));
verificar(
  'o private do Gestor ficou',
  await existe(t.collection('staff').doc('mgr').collection('private').doc('contacts')),
);
verificar('a conta de Auth do Gestor ficou', Boolean(await auth.getUser('mgr').catch(() => null)));
const claimsMgr = (await auth.getUser('mgr')).customClaims ?? {};
verificar(
  'os claims do Gestor ficaram intactos',
  claimsMgr.tenantId === TENANT && (claimsMgr.roles ?? []).includes('manager'),
);
verificar('--keep guardou os exercícios', await existe(t.collection('exercises').doc('ex_1')));
verificar('--keep guardou as categorias', await existe(t.collection('exerciseCategories').doc('c1')));
verificar('a conta de OUTRO estúdio não foi tocada', Boolean(await auth.getUser('alheio').catch(() => null)));

// O que TEM de desaparecer.
verificar('o instrutor saiu de staff', !(await existe(t.collection('staff').doc('inst'))));
verificar(
  'o private do instrutor saiu com ele',
  !(await existe(t.collection('staff').doc('inst').collection('private').doc('contacts'))),
);
verificar('os membros foram todos', (await contar(t.collection('members'))) === 0);
verificar(
  'as avaliações (subcoleção) foram atrás do membro',
  !(await existe(t.collection('members').doc('m1').collection('assessments').doc('a1'))),
);
verificar(
  'os pagamentos (subcoleção) foram atrás do membro',
  !(await existe(t.collection('members').doc('m1').collection('paymentRecords').doc('p1'))),
);
verificar(
  'as marcações (subcoleção) foram atrás da ocorrência',
  !(await existe(t.collection('sessionOccurrences').doc('occ1').collection('bookings').doc('m1'))),
);
verificar(
  'as presenças (subcoleção) foram atrás da ocorrência',
  !(await existe(t.collection('sessionOccurrences').doc('occ1').collection('attendance').doc('m1'))),
);
verificar(
  'os slots (subcoleção) foram atrás do horário livre',
  !(await existe(t.collection('freeTrainingSchedules').doc('w1').collection('slots').doc('s1'))),
);
verificar('a config foi', (await contar(t.collection('config'))) === 0);
verificar('os serviços foram', (await contar(t.collection('services'))) === 0);
verificar('os planos foram', (await contar(t.collection('plans'))) === 0);
verificar('as subscrições foram', (await contar(t.collection('subscriptions'))) === 0);
verificar('a utilização foi', (await contar(t.collection('usage'))) === 0);
verificar('a vitrina foi', (await contar(t.collection('public'))) === 0);
verificar('a conta de Auth do aluno foi', !(await auth.getUser('m1').catch(() => null)));
verificar('a conta de Auth do instrutor foi', !(await auth.getUser('inst').catch(() => null)));
verificar('a conta órfã (sem documento) foi', !(await auth.getUser('orfao').catch(() => null)));
verificar('os _rateLimits foram', (await contar(db.collection('_rateLimits'))) === 0);

// Nenhum documento órfão em lado nenhum: a prova de que o recursiveDelete
// chegou ao fundo. Uma query de grupo de coleção vê o que a consola não vê.
for (const grupo of ['bookings', 'attendance', 'assessments', 'paymentRecords', 'slots', 'private']) {
  const snap = await db.collectionGroup(grupo).get();
  const forasDoGestor = snap.docs.filter((d) => !d.ref.path.includes('/staff/mgr/'));
  verificar(`nenhum órfão em ${grupo} (grupo de coleção)`, forasDoGestor.length === 0);
}

console.log('');
if (falhas.length === 0) {
  console.log('TUDO OK — o script faz o que diz.');
} else {
  console.log(`${falhas.length} FALHA(S).`);
  process.exitCode = 1;
}
