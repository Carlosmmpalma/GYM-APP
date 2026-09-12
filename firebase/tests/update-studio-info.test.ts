// A informação pública do estúdio, escrita pelo Gestor a partir da app.
//
// Esteve em configuração da build, e mudar o telefone do ginásio obrigava
// a um developer, uma build nova e uma revisão da App Store. Passou para
// `tenants/{t}/public/info` — o caminho que se lê sem sessão.
//
// Como esse caminho é público, a escrita não pode ser direta do cliente:
// passa por esta função. O que interessa provar é quem pode escrever, e
// que o que lá fica não deixa o Gestor publicar um botão partido.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import {
  deleteApp,
  initializeApp as initializeClientApp,
  type FirebaseApp,
} from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_studio_info';
const MANAGER = 'si_gestor';
const MEMBER = 'si_aluno';
const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-studio-info');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let managerFns: Functions;
let memberFns: Functions;

async function clientFor(uid: string, roles: string[]) {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    `si-${uid}`,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(uid, { tenantId: TENANT_ID, roles }),
  );
  const fns = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(fns, 'localhost', 5001);
  return fns;
}

async function info() {
  const doc = await adminFirestore
    .doc(`tenants/${TENANT_ID}/public/info`)
    .get();
  return doc.data() ?? {};
}

const validos = {
  address: 'Rua de Exemplo 1, Lisboa',
  phone: '210 000 000',
  email: 'geral@exemplo.test',
  mapsUrl: 'https://maps.example.test/nxt',
  privacyPolicyUrl: 'https://exemplo.test/privacidade',
  openingHours: [
    { days: 'Segunda a sexta', hours: '07:00 - 22:00' },
    { days: 'Sábado', hours: '09:00 - 13:00' },
  ],
};

beforeAll(async () => {
  await adminFirestore.recursiveDelete(
    adminFirestore.doc(`tenants/${TENANT_ID}`),
  );
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Estúdio' });
  for (const uid of [MANAGER, MEMBER]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }
  managerFns = await clientFor(MANAGER, ['manager']);
  memberFns = await clientFor(MEMBER, ['member']);
}, 60_000);

afterAll(async () => {
  await adminFirestore.recursiveDelete(
    adminFirestore.doc(`tenants/${TENANT_ID}`),
  );
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

describe('updateStudioInfo', () => {
  it('o Gestor escreve a informação pública do estúdio', async () => {
    await httpsCallable(managerFns, 'updateStudioInfo')(validos);

    const guardado = await info();
    expect(guardado.address).toBe(validos.address);
    expect(guardado.privacyPolicyUrl).toBe(validos.privacyPolicyUrl);
    expect(guardado.openingHours).toHaveLength(2);
  });

  it('um aluno não consegue', async () => {
    // O documento é lido por toda a gente; a escrita é do estúdio.
    await expect(
      httpsCallable(memberFns, 'updateStudioInfo')(validos),
    ).rejects.toThrow();
  });

  it('recusa um endereço sem esquema', async () => {
    // Um "URL" assim abre uma página em branco no telemóvel, e ninguém
    // saberia porquê — o botão simplesmente não faz nada.
    await expect(
      httpsCallable(managerFns, 'updateStudioInfo')({
        ...validos,
        privacyPolicyUrl: 'exemplo.test/privacidade',
      }),
    ).rejects.toThrow();
  });

  it('aceita campos vazios — querem dizer "não mostrar"', async () => {
    // Bloquear o Gestor de guardar a morada enquanto não tiver o horário
    // todo seria pior do que deixá-lo fazer uma coisa de cada vez.
    await httpsCallable(managerFns, 'updateStudioInfo')({
      ...validos,
      mapsUrl: '',
      email: '',
    });

    const guardado = await info();
    expect(guardado.mapsUrl).toBe('');
    expect(guardado.address).toBe(validos.address);
  });

  it('não guarda linhas de horário sem horas', async () => {
    // Inclui as que têm o dia preenchido e a hora em branco: o ecrã de
    // gestão sugere os dias da semana, por isso "Sábado" sem horas é o
    // caso normal de quem fecha ao fim de semana. Guardá-lo punha na
    // vitrina um dia seguido de nada, que se lê como um erro — foi
    // assim que apareceu, a testar a app a correr.
    await httpsCallable(managerFns, 'updateStudioInfo')({
      ...validos,
      openingHours: [
        { days: 'Segunda a sexta', hours: '07:00 - 22:00' },
        { days: 'Sábado', hours: '' },
        { days: '', hours: '' },
      ],
    });

    expect((await info()).openingHours).toHaveLength(1);
  });
});
