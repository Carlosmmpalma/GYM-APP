// O mapa de aulas que se vê sem conta, do fim ao princípio.
//
// É derivado das `sessionSeries` ativas pelo mesmo cron diário que gera
// as ocorrências — ver `lib/publicSchedule.ts` sobre porque é derivado
// em vez de escrito à mão pelo Gestor. O que interessa provar:
//
//   1. que ele aparece mesmo, com o nome certo (modalidade quando
//      existe, senão o serviço);
//   2. que NÃO leva nada que não devia ser público;
//   3. que uma série desativada desaparece da vitrina — um horário
//      público que anuncia uma aula que já não existe manda pessoas ao
//      ginásio para nada.

import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { deleteApp, initializeApp as initializeClientApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithCustomToken } from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_vitrina_cron';
const MANAGER = 'vitrina_gestor';
const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

// Pelo emulador, e não importando a função diretamente: `firebase/tests`
// e `firebase/functions` têm cada um a sua cópia do `firebase-admin`, com
// registos de apps separados — chamar o código da função a partir daqui
// dava-lhe uma app por omissão que não existe (`app/no-app`). É também
// como o resto da suite o faz, e prova o caminho verdadeiro.
const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-vitrina');
const adminAuth = getAdminAuth(adminApp);
const firestore = getFirestore(adminApp);
const tenantRef = firestore.collection('tenants').doc(TENANT_ID);

let managerFns: Functions;
const clientApps: ReturnType<typeof initializeClientApp>[] = [];

async function gerar() {
  await httpsCallable(managerFns, 'generateRecurringOccurrencesNow')({});
}

async function vitrina() {
  const snap = await tenantRef.collection('public').doc('schedule').get();
  return (snap.get('entries') ?? []) as Record<string, unknown>[];
}

beforeAll(async () => {
  await firestore.recursiveDelete(tenantRef);
  await tenantRef.set({ name: 'Estúdio da Vitrina', timeZone: 'Europe/Lisbon' });
  await tenantRef.collection('services').doc('svc_aulas').set({
    name: 'Aula de Grupo',
    active: true,
  });
  await tenantRef.collection('modalities').doc('mod_hyrox').set({
    name: 'Hyrox',
    active: true,
  });

  const base = {
    serviceId: 'svc_aulas',
    instructorId: 'instrutor_secreto',
    startDate: Timestamp.fromDate(new Date('2026-01-05T00:00:00Z')),
    status: 'active',
  };

  // Com modalidade: é o nome da modalidade que se anuncia.
  await tenantRef.collection('sessionSeries').doc('s_hyrox').set({
    ...base,
    modalityId: 'mod_hyrox',
    dayOfWeek: 1,
    startTime: '19:00',
    durationMinutes: 60,
    capacity: 8,
  });
  // Sem modalidade: cai no nome do serviço.
  await tenantRef.collection('sessionSeries').doc('s_generica').set({
    ...base,
    modalityId: null,
    dayOfWeek: 3,
    startTime: '07:30',
    durationMinutes: 45,
    capacity: 12,
  });
  // Cancelada: não deve aparecer em lado nenhum.
  await tenantRef.collection('sessionSeries').doc('s_antiga').set({
    ...base,
    modalityId: null,
    dayOfWeek: 5,
    startTime: '21:00',
    durationMinutes: 60,
    capacity: 5,
    status: 'cancelled',
  });


  await adminAuth
    .createUser({ uid: MANAGER, email: `${MANAGER}@example.test`, password: 'TestPass123!' })
    .catch(() => undefined);

  const clientApp = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    'vitrina-gestor',
  );
  clientApps.push(clientApp);
  const auth = getAuth(clientApp);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(
    auth,
    await adminAuth.createCustomToken(MANAGER, {
      tenantId: TENANT_ID,
      roles: ['manager'],
    }),
  );
  managerFns = getFunctions(clientApp, FUNCTIONS_REGION);
  connectFunctionsEmulator(managerFns, 'localhost', 5001);
}, 60_000);

afterAll(async () => {
  await firestore.recursiveDelete(tenantRef);
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

describe('A vitrina que o cron publica', () => {
  it('anuncia as aulas ativas, pela modalidade quando existe', async () => {
    await gerar();
    const entries = await vitrina();

    expect(entries).toHaveLength(2);
    // Ordenada por dia e hora: é assim que se lê um cartaz.
    expect(entries[0]).toMatchObject({
      name: 'Hyrox',
      dayOfWeek: 1,
      startTime: '19:00',
      durationMinutes: 60,
      capacity: 8,
    });
    expect(entries[1]).toMatchObject({
      name: 'Aula de Grupo',
      dayOfWeek: 3,
      startTime: '07:30',
    });
  });

  it('não anuncia a série cancelada', async () => {
    await gerar();
    const nomes = (await vitrina()).map((e) => e.dayOfWeek);
    expect(nomes).not.toContain(5);
  });

  it('não deixa escapar nada que não seja de cartaz', async () => {
    // O risco real de um documento público não é o que lá se põe de
    // propósito — é o que vai por arrasto quando alguém acrescenta um
    // campo à série. Isto falha assim que isso acontecer.
    await gerar();
    const entries = await vitrina();

    for (const entry of entries) {
      expect(Object.keys(entry).sort()).toEqual([
        'capacity',
        'dayOfWeek',
        'durationMinutes',
        'name',
        'startTime',
      ]);
      expect(JSON.stringify(entry)).not.toContain('instrutor_secreto');
    }
  });

  it('é reescrita a cada corrida, não acumulada', async () => {
    await gerar();
    await gerar();
    expect(await vitrina()).toHaveLength(2);
  });
});
