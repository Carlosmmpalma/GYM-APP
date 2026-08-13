// Seed de desenvolvimento — corre SÓ contra o Firebase Emulator Suite.
//
// Cria:
//   1. O tenant real "NXT Performance Studio" + o primeiro Gestor (Leo).
//   2. Um tenant fantasma, só para testes manuais de isolamento
//      (guia-desenvolvimento.md, Fase 1: "Cria um segundo 'tenant
//      fantasma' só para os testes de isolamento tentarem invadir").
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
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  console.log(
    `✓ membro "${tenantId}" nº "${memberNumber}" / password "${password}" (uid=${user.uid})`,
  );
}

async function main() {
  console.log(`A semear contra o emulador (projectId=${PROJECT_ID})...\n`);

  await upsertTenant(REAL_TENANT_ID, 'NXT Performance Studio');
  await seedManager();
  await seedMember({
    tenantId: REAL_TENANT_ID,
    memberNumber: '000001',
    name: 'Rita Ferreira',
    password: 'MemberPass123!',
  });

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
      'pelo número em si).',
  );
}

main().catch((err) => {
  console.error('Falhou:', err);
  process.exitCode = 1;
});
