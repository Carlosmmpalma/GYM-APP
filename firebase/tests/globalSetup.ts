import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

/**
 * Limpa os contadores do rate limiter antes de cada corrida da suite.
 *
 * As funções sensíveis (criar contas, marcar, apagar dados) têm limite
 * de chamadas por utilizador — 20 em 5 minutos, por exemplo. Os
 * contadores vivem em `_rateLimits/{uid}__{operacao}` e, no emulador,
 * **sobrevivem entre corridas**: correr a suite duas vezes seguidas
 * fazia testes passar à primeira e falhar à segunda com "Demasiados
 * pedidos em pouco tempo", que parece contaminação entre testes e é só
 * o limitador a funcionar como deve.
 *
 * Apagar aqui — uma vez, antes de tudo — é honesto: nenhum destes
 * testes anda a provar o limitador (esse tem os seus), e um teste que
 * falha à segunda corrida é um teste em que ninguém confia.
 */
export default async function setup() {
  process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';

  const app = initializeApp({ projectId: 'demo-gym-saas-dev' }, 'global-setup');
  const firestore = getFirestore(app);

  const snapshot = await firestore.collection('_rateLimits').get();
  if (snapshot.empty) return;

  const batch = firestore.batch();
  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
}
