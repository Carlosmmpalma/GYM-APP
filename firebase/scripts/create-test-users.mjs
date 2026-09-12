// Cria (e remove) contas de TESTE num projeto real.
//
// Porquê um script separado do `seed.mjs`: o seed corre só contra o
// emulador e cria um estúdio inteiro (serviços, séries, planos). Aqui o
// estúdio já existe e é o verdadeiro — só faltam alunos para clicar.
//
//   node create-test-users.mjs --project=gym-sas \
//     --tenant=nxt_performance_studio --count=5 --yes
//
// E para os apagar a todos quando deixarem de ser precisos:
//
//   node create-test-users.mjs --project=gym-sas \
//     --tenant=nxt_performance_studio --delete --yes
//
// ---------------------------------------------------------------------
// Duas decisões que valem a pena explicar, porque isto escreve na base
// de dados a sério:
//
// 1. Os números de sócio de teste começam em 900001. Os reais começam
//    em 000001 e sobem — as duas gamas nunca se cruzam, e um número que
//    comece por 9 é reconhecível de relance numa listagem.
//
// 2. Mesmo assim, o `--delete` NÃO se guia pelo número. Guia-se pelo
//    campo `isTestAccount: true` gravado no documento. Se um dia
//    alguém criar um sócio real com um número alto, uma convenção de
//    nomes apagava-o; uma marca explícita não.
// ---------------------------------------------------------------------

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectId = arg('project');
const tenantId = arg('tenant');
const count = Number(arg('count', '5'));
const firstNumber = Number(arg('from', '900001'));
const password = arg('password', 'Teste1234');
const withInstructor = process.argv.includes('--with-instructor');
const deleting = process.argv.includes('--delete');
const force = process.argv.includes('--force');
const confirmed = process.argv.includes('--yes');

const missing = Object.entries({ project: projectId, tenant: tenantId })
  .filter(([, value]) => !value)
  .map(([key]) => `--${key}`);

if (missing.length > 0) {
  console.error(`Faltam argumentos: ${missing.join(', ')}`);
  process.exit(1);
}

if (!deleting && (!Number.isInteger(count) || count < 1 || count > 50)) {
  console.error('--count tem de ser um inteiro entre 1 e 50.');
  process.exit(1);
}

// O Firebase Auth recusa passwords com menos de 6 caracteres, e a
// mensagem de erro que devolve é obscura. Mais vale falhar aqui.
if (!deleting && password.length < 6) {
  console.error('A password precisa de pelo menos 6 caracteres (regra do Firebase Auth).');
  process.exit(1);
}

const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const where = usingEmulator ? '[EMULADOR]' : '[PROJETO REAL]';

if (!confirmed) {
  console.error(
    deleting
      ? `Vai APAGAR todas as contas de teste de "${tenantId}" em "${projectId}" ${where}.\n` +
          'Confirma acrescentando --yes ao comando.'
      : `Vai criar ${count} alunos de teste em "${tenantId}" / "${projectId}" ${where}.\n` +
          'Confirma acrescentando --yes ao comando.',
  );
  process.exit(1);
}

initializeApp({ projectId });
const auth = getAuth();
const firestore = getFirestore();

const tenantRef = firestore.collection('tenants').doc(tenantId);
const membersRef = tenantRef.collection('members');

// Espelho de `toDomainLabel` em lib/core/config/login_identifier.dart.
// O Firebase Auth real recusa `_` no domínio (`auth/invalid-email`); o
// emulador aceita. Ver o comentário longo no ficheiro Dart.
function toDomainLabel(tenantId) {
  const collapsed = tenantId
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return collapsed === '' ? 'tenant' : collapsed;
}

function syntheticEmail(memberNumber) {
  return `member-${memberNumber}@${toDomainLabel(tenantId)}.gymsaas.internal`;
}

const INSTRUCTOR_EMAIL = `instrutor.teste@${toDomainLabel(tenantId)}.gymsaas.internal`;

// ------------------------------------------------------------- criar

async function createMember(index) {
  const memberNumber = String(firstNumber + index);
  const name = `Aluno Teste ${index + 1}`;
  const email = syntheticEmail(memberNumber);

  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, { password, displayName: name });
    console.log(`· ${memberNumber} já existia — password reposta`);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, password, displayName: name });
  }

  await auth.setCustomUserClaims(user.uid, { tenantId, roles: ['member'] });

  await membersRef.doc(user.uid).set(
    {
      userId: user.uid,
      memberNumber,
      name,
      status: 'active',
      passwordTemporaria: false,
      // É esta marca que o `--delete` procura. Ver o cabeçalho.
      isTestAccount: true,
      // Consentimento já dado, senão cada login destes parava no ecrã
      // de RGPD antes de se chegar ao que se queria testar. Para VER
      // esse ecrã, cria um aluno pela app — nasce sem consentimento.
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

  console.log(`✓ nº sócio ${memberNumber}  ·  ${name}`);
  return memberNumber;
}

async function createInstructor() {
  const name = 'Instrutor Teste';
  let user;
  try {
    user = await auth.getUserByEmail(INSTRUCTOR_EMAIL);
    await auth.updateUser(user.uid, { password, displayName: name });
    console.log('· instrutor de teste já existia — password reposta');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email: INSTRUCTOR_EMAIL, password, displayName: name });
  }

  await auth.setCustomUserClaims(user.uid, { tenantId, roles: ['instructor'] });

  // Os serviços que ele leciona. Sem isto o instrutor entra na app e
  // NÃO CONSEGUE criar aulas: as Security Rules exigem que a aula seja
  // de um serviço dele (`instructorOwnsSession`), e o ecrã dele
  // escondia o atalho sem dizer porquê.
  //
  // Uma conta de teste leciona tudo — não há nada a decidir aqui, e
  // deixá-la sem serviços era criar um instrutor que não faz nada.
  const services = await tenantRef.collection('services').get();
  const serviceIds = services.docs
    .filter((doc) => doc.get('active') !== false)
    .map((doc) => doc.id);

  await tenantRef
    .collection('staff')
    .doc(user.uid)
    .set(
      {
        userId: user.uid,
        name,
        email: INSTRUCTOR_EMAIL,
        roles: ['instructor'],
        status: 'active',
        passwordTemporaria: false,
        isTestAccount: true,
        serviceIds,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  console.log(
    `✓ instrutor  ·  ${INSTRUCTOR_EMAIL}  ` +
      `(${serviceIds.length} serviço(s) atribuídos)`,
  );
}

// ------------------------------------------------------------ apagar

/**
 * Apagar um membro que ainda tem marcações ativas deixava o
 * `activeBookingCount` da aula a contar alguém que já não existe — e
 * esse contador é o que decide se há vagas. A aula ficava com uma vaga
 * fantasma para sempre, porque nada a volta a recalcular.
 *
 * Por isso: conta primeiro, recusa depois. Cancelar pela app é o
 * caminho correto (passa pelas Cloud Functions, que atualizam o
 * contador e devolvem a utilização ao plano).
 */
async function activeBookingCount(uid) {
  const snapshot = await firestore
    .collectionGroup('bookings')
    .where('memberId', '==', uid)
    .where('status', '==', 'booked')
    .get();
  return snapshot.size;
}

async function deleteTestAccounts() {
  const [members, staff] = await Promise.all([
    membersRef.where('isTestAccount', '==', true).get(),
    tenantRef.collection('staff').where('isTestAccount', '==', true).get(),
  ]);

  if (members.empty && staff.empty) {
    console.log('Não há contas de teste neste tenant. Nada a fazer.');
    return;
  }

  let blocked = 0;
  for (const doc of members.docs) {
    const bookings = await activeBookingCount(doc.id);
    if (bookings > 0 && !force) {
      console.error(
        `✗ ${doc.get('memberNumber')} tem ${bookings} marcação(ões) ativa(s) — não apagado.`,
      );
      blocked += 1;
      continue;
    }
    await auth.deleteUser(doc.id).catch((e) => {
      if (e.code !== 'auth/user-not-found') throw e;
    });
    await doc.ref.delete();
    console.log(`✓ apagado nº ${doc.get('memberNumber')}`);
  }

  for (const doc of staff.docs) {
    await auth.deleteUser(doc.id).catch((e) => {
      if (e.code !== 'auth/user-not-found') throw e;
    });
    await doc.ref.delete();
    console.log(`✓ apagado staff ${doc.get('email')}`);
  }

  if (blocked > 0) {
    console.error(
      `\n${blocked} conta(s) ficaram por apagar. Cancela as marcações pela app ` +
        '(Gestão › a aula › o aluno › Cancelar) e volta a correr.\n' +
        'O --force ignora esta verificação, mas deixa as vagas dessas aulas ' +
        'ocupadas por alguém que já não existe.',
    );
    process.exitCode = 1;
  }
}

// -------------------------------------------------------------- main

if (deleting) {
  await deleteTestAccounts();
} else {
  const tenantSnapshot = await tenantRef.get();
  if (!tenantSnapshot.exists) {
    console.error(
      `O tenant "${tenantId}" não existe em "${projectId}".\n` +
        'Corre primeiro o create-first-manager.mjs.',
    );
    process.exit(1);
  }

  const numbers = [];
  for (let i = 0; i < count; i += 1) {
    numbers.push(await createMember(i));
  }
  if (withInstructor) await createInstructor();

  console.log(
    '\nPronto. Entra na app com o NÚMERO DE SÓCIO (não o email):\n' +
      `  ${numbers[0]} … ${numbers[numbers.length - 1]}\n` +
      `  password: ${password}\n\n` +
      'Nota: nascem sem plano nem subscrição, por isso ainda não conseguem\n' +
      'marcar aulas. Atribui-lhes um plano em Gestão › Utilizadores.\n\n' +
      'Para os apagar mais tarde: o mesmo comando com --delete --yes',
  );
}
