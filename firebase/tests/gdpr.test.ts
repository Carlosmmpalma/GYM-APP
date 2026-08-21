// Fase 11 (RGPD) — as garantias que a lei exige, testadas a sério
// contra o emulador em vez de assumidas.
//
// Três coisas que interessam a uma autoridade de proteção de dados, e
// que uma revisão de código sozinha não prova:
//
//   1. O consentimento para dados de saúde é aplicado pelo SERVIDOR.
//      Esconder o botão na UI não é proteção nenhuma — a garantia tem
//      de vir das Security Rules, senão uma escrita direta contorna-a.
//   2. A exportação (artigo 15.º) devolve mesmo tudo, e não deixa um
//      membro ver os dados de outro.
//   3. O apagamento (artigo 17.º) apaga os dados de saúde e ao mesmo
//      tempo RETÉM os registos de pagamento anonimizados — a exceção da
//      alínea b) do n.º 3, que a contabilidade portuguesa obriga.
//
// Precisa dos emuladores Firestore + Functions + Auth e de
// `firebase/functions` compilado. Ver `booking-concurrency.test.ts`.

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
  connectFirestoreEmulator,
  doc,
  getFirestore,
  setDoc,
  type Firestore,
} from 'firebase/firestore';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type Functions,
} from 'firebase/functions';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const PROJECT_ID = 'demo-gym-saas-dev';
const TENANT_ID = 'tenant_gdpr_test';
const MEMBER_ID = 'member_gdpr_test';
const OTHER_MEMBER_ID = 'member_gdpr_other';
const MANAGER_ID = 'manager_gdpr_test';
const INSTRUCTOR_ID = 'instructor_gdpr_test';

const FUNCTIONS_REGION = 'europe-west1';

process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, 'admin-gdpr-test');
const adminAuth = getAdminAuth(adminApp);
const adminFirestore = getAdminFirestore(adminApp);

const clientApps: FirebaseApp[] = [];
let memberFunctions: Functions;
let otherMemberFunctions: Functions;
let managerFunctions: Functions;
let instructorFirestore: Firestore;

async function signedInClient(
  appName: string,
  uid: string,
  claims: { tenantId: string; roles: string[] },
): Promise<{ functions: Functions; firestore: Firestore }> {
  const app = initializeClientApp(
    { projectId: PROJECT_ID, apiKey: 'demo-api-key' },
    appName,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  await signInWithCustomToken(auth, await adminAuth.createCustomToken(uid, claims));

  // A região TEM de bater certo com o `setGlobalOptions` de
  // `functions/src/index.ts`: com a região errada, o cliente procura as
  // funções em `us-central1`, onde não existe nada, e recebe
  // `not-found` em tudo.
  const functions = getFunctions(app, FUNCTIONS_REGION);
  connectFunctionsEmulator(functions, 'localhost', 5001);

  const firestore = getFirestore(app);
  connectFirestoreEmulator(firestore, 'localhost', 8080);

  return { functions, firestore };
}

beforeAll(async () => {
  await adminFirestore.recursiveDelete(adminFirestore.doc(`tenants/${TENANT_ID}`));
  await adminFirestore.doc(`tenants/${TENANT_ID}`).set({ name: 'Tenant RGPD' });

  for (const [uid, number] of [
    [MEMBER_ID, '000001'],
    [OTHER_MEMBER_ID, '000002'],
  ] as const) {
    await adminFirestore.doc(`tenants/${TENANT_ID}/members/${uid}`).set({
      name: `Membro ${number}`,
      memberNumber: number,
      status: 'active',
      nif: '123456789',
      phone: '912345678',
    });
  }

  for (const uid of [MEMBER_ID, OTHER_MEMBER_ID, MANAGER_ID, INSTRUCTOR_ID]) {
    await adminAuth
      .createUser({ uid, email: `${uid}@example.test`, password: 'TestPass123!' })
      .catch(() => undefined);
  }

  const member = await signedInClient('gdpr-member', MEMBER_ID, {
    tenantId: TENANT_ID,
    roles: ['member'],
  });
  memberFunctions = member.functions;

  const other = await signedInClient('gdpr-other', OTHER_MEMBER_ID, {
    tenantId: TENANT_ID,
    roles: ['member'],
  });
  otherMemberFunctions = other.functions;

  const manager = await signedInClient('gdpr-manager', MANAGER_ID, {
    tenantId: TENANT_ID,
    roles: ['manager'],
  });
  managerFunctions = manager.functions;

  const instructor = await signedInClient('gdpr-instructor', INSTRUCTOR_ID, {
    tenantId: TENANT_ID,
    roles: ['instructor'],
  });
  instructorFirestore = instructor.firestore;
}, 60_000);

afterAll(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
});

describe('RGPD — consentimento para dados de saúde (artigo 9.º)', () => {
  it('SEM consentimento, nem um Instrutor consegue escrever uma avaliação',
    async () => {
      // O ponto do teste: a garantia é do servidor. O Instrutor está
      // autenticado, tem o role certo e escreve diretamente ao Firestore
      // — a UI não está no caminho.
      await expect(
        setDoc(
          doc(
            instructorFirestore,
            `tenants/${TENANT_ID}/members/${MEMBER_ID}/assessments/a1`,
          ),
          { peso: 80, createdAt: new Date(), instructorId: INSTRUCTOR_ID },
        ),
      ).rejects.toThrow();
    });

  it('depois de o próprio membro consentir, a avaliação passa', async () => {
    await httpsCallable(memberFunctions, 'recordConsent')({
      privacyPolicyVersion: 1,
      healthDataGranted: true,
    });

    await expect(
      setDoc(
        doc(
          instructorFirestore,
          `tenants/${TENANT_ID}/members/${MEMBER_ID}/assessments/a1`,
        ),
        { peso: 80, createdAt: new Date(), instructorId: INSTRUCTOR_ID },
      ),
    ).resolves.toBeUndefined();
  });

  it('o consentimento fica registado com timestamp do SERVIDOR', async () => {
    // Artigo 7.º, n.º 1 — tem de ser demonstrável. Um campo escrito pelo
    // cliente com uma data escolhida por ele não demonstra nada; daí
    // passar por Cloud Function.
    const snapshot = await adminFirestore
      .doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`)
      .get();
    const consent = snapshot.get('consent');
    expect(consent.healthDataGranted).toBe(true);
    expect(consent.privacyPolicyVersion).toBe(1);
    expect(consent.acceptedAt).toBeTruthy();

    // E o histórico, não só o estado atual: "consentiu em X, retirou em
    // Y" é o que uma autoridade quer ver.
    const log = await adminFirestore
      .collection(`tenants/${TENANT_ID}/members/${MEMBER_ID}/consentLog`)
      .get();
    expect(log.size).toBeGreaterThanOrEqual(1);
  });

  it('retirado o consentimento, volta a ser recusado', async () => {
    await httpsCallable(memberFunctions, 'recordConsent')({
      privacyPolicyVersion: 1,
      healthDataGranted: false,
    });

    await expect(
      setDoc(
        doc(
          instructorFirestore,
          `tenants/${TENANT_ID}/members/${MEMBER_ID}/assessments/a2`,
        ),
        { peso: 81, createdAt: new Date(), instructorId: INSTRUCTOR_ID },
      ),
    ).rejects.toThrow();
  });
});

describe('RGPD — exportação (artigos 15.º/20.º)', () => {
  it('um membro exporta os seus próprios dados', async () => {
    const result = await httpsCallable(memberFunctions, 'exportMemberData')({});
    const data = result.data as Record<string, unknown>;

    expect(data.memberId).toBe(MEMBER_ID);
    expect((data.profile as Record<string, unknown>).nif).toBe('123456789');
    // A avaliação criada enquanto havia consentimento continua lá — o
    // consentimento retirado impede novas, não apaga as antigas.
    expect((data.assessments as unknown[]).length).toBe(1);
    expect((data.consentLog as unknown[]).length).toBeGreaterThanOrEqual(2);
  });

  it('um membro NÃO consegue exportar os dados de outro', async () => {
    await expect(
      httpsCallable(otherMemberFunctions, 'exportMemberData')({
        memberId: MEMBER_ID,
      }),
    ).rejects.toThrow();
  });

  it('um Gestor consegue, porque é ele quem responde ao pedido',
    async () => {
      const result = await httpsCallable(managerFunctions, 'exportMemberData')({
        memberId: MEMBER_ID,
      });
      expect((result.data as Record<string, unknown>).memberId).toBe(MEMBER_ID);
    });
});

describe('RGPD — apagamento (artigo 17.º)', () => {
  it('recusa se o número de sócio de confirmação não bater certo', async () => {
    await expect(
      httpsCallable(managerFunctions, 'deleteMemberData')({
        memberId: MEMBER_ID,
        confirmMemberNumber: '999999',
      }),
    ).rejects.toThrow();
  });

  it('apaga os dados de saúde mas RETÉM os pagamentos, anonimizados',
    async () => {
      await adminFirestore
        .doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}/paymentRecords/2026-08`)
        .set({
          year: 2026,
          month: 8,
          status: 'paid',
          amount: 45,
          memberName: 'Membro 000001',
        });

      const result = await httpsCallable(managerFunctions, 'deleteMemberData')({
        memberId: MEMBER_ID,
        confirmMemberNumber: '000001',
      });
      const report = result.data as {
        deleted: Record<string, number>;
        anonymizedPaymentRecords: number;
      };

      expect(report.deleted.assessments).toBe(1);
      expect(report.anonymizedPaymentRecords).toBe(1);

      // Dados de saúde: fora.
      const assessments = await adminFirestore
        .collection(`tenants/${TENANT_ID}/members/${MEMBER_ID}/assessments`)
        .get();
      expect(assessments.empty).toBe(true);

      // Registo financeiro: fica, sem nada que identifique a pessoa.
      const payment = await adminFirestore
        .doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}/paymentRecords/2026-08`)
        .get();
      expect(payment.exists).toBe(true);
      expect(payment.get('amount')).toBe(45);
      expect(payment.get('memberName')).toBeUndefined();
      expect(payment.get('anonymizedAt')).toBeTruthy();

      // Perfil: sem identidade, mas o documento sobrevive para segurar
      // os pagamentos retidos.
      const member = await adminFirestore
        .doc(`tenants/${TENANT_ID}/members/${MEMBER_ID}`)
        .get();
      expect(member.get('nif')).toBeUndefined();
      expect(member.get('phone')).toBeUndefined();
      expect(member.get('consent')).toBeUndefined();
      expect(member.get('status')).toBe('deleted');

      // E a conta de acesso desaparece.
      await expect(adminAuth.getUser(MEMBER_ID)).rejects.toThrow();
    }, 30_000);

  it('um membro não consegue apagar os dados de ninguém', async () => {
    await expect(
      httpsCallable(otherMemberFunctions, 'deleteMemberData')({
        memberId: OTHER_MEMBER_ID,
        confirmMemberNumber: '000002',
      }),
    ).rejects.toThrow();
  });
});
