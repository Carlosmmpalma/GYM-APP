// Cria o PRIMEIRO Gestor de um estúdio — o único que não se consegue
// criar pela app.
//
// Porquê um script: criar staff pela app exige já ser Gestor
// (intencional), e a consola do Firebase **não sabe atribuir custom
// claims** — sem `tenantId` e `roles` no token, a conta autentica-se e
// fica presa num estado que nenhum ecrã trata. Ou seja, sem isto não há
// forma de entrar num projeto acabado de criar.
//
// Corre com credenciais de administrador do projeto:
//
//   gcloud auth application-default login
//   node create-first-manager.mjs \
//     --project=o-id-do-projeto \
//     --tenant=nxt_performance_studio \
//     --name="Leo Gil" \
//     --email=leo@exemplo.pt \
//     --password='UmaPasswordForte123!' \
//     --yes
//
// Contra o emulador (para experimentar sem risco), basta exportar
// FIRESTORE_EMULATOR_HOST=localhost:8080 e
// FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 antes de correr.

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

function arg(name) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : undefined;
}

const projectId = arg('project');
const tenantId = arg('tenant');
const name = arg('name');
const email = arg('email');
const password = arg('password');
const confirmed = process.argv.includes('--yes');

const missing = Object.entries({ project: projectId, tenant: tenantId, name, email, password })
  .filter(([, value]) => !value)
  .map(([key]) => `--${key}`);

if (missing.length > 0) {
  console.error(`Faltam argumentos: ${missing.join(', ')}`);
  console.error('Ver o cabeçalho deste ficheiro para o comando completo.');
  process.exit(1);
}

const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

// Este script escreve numa base de dados REAL a não ser que o emulador
// esteja configurado. Uma confirmação explícita é barata; um Gestor
// criado no projeto errado não é.
if (!confirmed) {
  console.error(
    `Vai criar um GESTOR em "${projectId}" (tenant "${tenantId}")` +
      `${usingEmulator ? ' [EMULADOR]' : ' [PROJETO REAL]'}.\n` +
      'Confirma acrescentando --yes ao comando.',
  );
  process.exit(1);
}

initializeApp({ projectId });
const auth = getAuth();
const firestore = getFirestore();

const tenantRef = firestore.collection('tenants').doc(tenantId);

// O documento do tenant tem de existir: é dele que sai o fuso horário
// usado para gerar as aulas das séries (ver `lib/timeZone.ts`).
const tenantSnapshot = await tenantRef.get();
if (!tenantSnapshot.exists) {
  await tenantRef.set({
    name,
    timezone: 'Europe/Lisbon',
    status: 'active',
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(`✓ tenant "${tenantId}" criado (timezone Europe/Lisbon)`);
} else {
  console.log(`· tenant "${tenantId}" já existia`);
}

let user;
try {
  user = await auth.getUserByEmail(email);
  console.log(`· conta ${email} já existia (uid=${user.uid})`);
} catch {
  user = await auth.createUser({ email, password, displayName: name });
  console.log(`✓ conta ${email} criada (uid=${user.uid})`);
}

// É isto que a consola não faz, e sem o qual nada funciona.
await auth.setCustomUserClaims(user.uid, { tenantId, roles: ['manager'] });
console.log('✓ claims atribuídas: { tenantId, roles: ["manager"] }');

await tenantRef.collection('staff').doc(user.uid).set(
  {
    userId: user.uid,
    name,
    email,
    roles: ['manager'],
    status: 'active',
    // A password foi escolhida por quem correu o script, não é
    // temporária — não faz sentido obrigar a trocá-la no primeiro
    // acesso.
    passwordTemporaria: false,
    createdAt: FieldValue.serverTimestamp(),
  },
  { merge: true },
);
console.log('✓ documento de staff criado');

console.log(
  `\nPronto. Entra na app com ${email} e a password que escolheste.\n` +
    'A partir daqui, todos os outros utilizadores criam-se pela app ' +
    '(Gestão › Utilizadores).',
);
