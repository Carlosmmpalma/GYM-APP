// A vitrina pública: o ÚNICO sítio desta base de dados que se lê sem
// sessão.
//
// Abrir leitura sem autenticação num projeto multi-tenant é a mudança
// mais fácil de fazer mal e a mais cara de descobrir tarde. O que estes
// testes provam não é só que a vitrina se lê — é que ela não serviu de
// porta para o resto:
//
//   1. lê-se sem sessão nenhuma (é para isso que existe);
//   2. NÃO se escreve, nem sequer com sessão de Gestor (quem escreve é
//      a função agendada, com o Admin SDK);
//   3. não arrastou consigo o documento do tenant nem nenhuma coleção
//      vizinha — um utilizador anónimo continua a bater com o nariz na
//      porta em tudo o resto.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const TENANT = 'tenant_vitrina';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-gym-saas-dev-showcase-test',
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `tenants/${TENANT}/public/info`), {
      address: 'Rua de Exemplo 1',
      phone: '210 000 000',
    });
    await setDoc(doc(db, `tenants/${TENANT}/public/schedule`), {
      entries: [
        {
          name: 'Hyrox',
          dayOfWeek: 1,
          startTime: '19:00',
          durationMinutes: 60,
          capacity: 8,
        },
      ],
    });
    await setDoc(doc(db, `tenants/${TENANT}`), { name: 'Estúdio' });
    await setDoc(doc(db, `tenants/${TENANT}/members/m1`), { name: 'Rita' });
    await setDoc(doc(db, `tenants/${TENANT}/services/s1`), { name: 'Aulas' });
  });
});

describe('Vitrina pública', () => {
  it('lê-se SEM sessão nenhuma', async () => {
    // O ponto todo: quem instala a app antes de se inscrever, e quem a
    // revê na App Store, tem de ver o mapa de aulas.
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, `tenants/${TENANT}/public/schedule`)));
  });

  it('a informação do estúdio também se lê sem sessão', async () => {
    // Morada, contactos e horário: é o que quem instala a app antes de
    // se inscrever precisa de saber.
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, `tenants/${TENANT}/public/info`)));
  });

  it('NÃO se escreve sem sessão', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, `tenants/${TENANT}/public/schedule`), { entries: [] }),
    );
  });

  it('NÃO se escreve nem sendo Gestor do estúdio', async () => {
    // Deliberado: um documento público com escrita direta do cliente é
    // um convite a pôr lá o que não devia. Quem o escreve é a função
    // agendada, a partir das séries ativas.
    const db = testEnv
      .authenticatedContext('gestor', { tenantId: TENANT, roles: ['manager'] })
      .firestore();
    await assertFails(
      setDoc(doc(db, `tenants/${TENANT}/public/schedule`), { entries: [] }),
    );
  });
});

describe('A vitrina não abriu mais nada', () => {
  it('sem sessão, o documento do tenant continua fechado', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `tenants/${TENANT}`)));
  });

  it('sem sessão, os membros continuam fechados', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `tenants/${TENANT}/members/m1`)));
  });

  it('sem sessão, o catálogo de serviços continua fechado', async () => {
    // Os serviços são "quase públicos" (preços, nomes) e por isso são o
    // vizinho mais provável de se abrir por engano. Continuam fechados:
    // o que é para ver sem conta está na vitrina, e só lá.
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `tenants/${TENANT}/services/s1`)));
  });
});
