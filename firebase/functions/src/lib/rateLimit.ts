import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Fase 11 — limite de chamadas por utilizador e por operação.
 *
 * O que isto é e o que NÃO é: não substitui o App Check (que responde a
 * "isto vem da nossa app?"). Responde a outra pergunta — "esta conta
 * está a pedir mais do que uma pessoa consegue?". Protege contra uma
 * sessão roubada usada em ciclo, contra um bug de cliente que reenvia
 * sem parar, e contra o custo que qualquer um dos dois gera.
 *
 * Janela deslizante grosseira: um documento por (uid, operação) com um
 * contador e a hora de início da janela. Passada a janela, reinicia. Não
 * é exato nos limites (duas chamadas simultâneas podem ambas ver o
 * contador antigo) e não faz mal nenhum — a diferença entre 10 e 11
 * chamadas por minuto não interessa a ninguém; o que interessa é a
 * diferença entre 10 e 10 000.
 *
 * Vive numa transação para o `+1` não se perder entre pedidos
 * concorrentes, e falha ABERTO: se o Firestore não responder, a chamada
 * segue. Recusar operações legítimas por causa da infraestrutura do
 * próprio limitador seria pior do que o abuso que evita.
 */
export async function enforceRateLimit(params: {
  uid: string;
  operation: string;
  maxCalls: number;
  windowSeconds: number;
}): Promise<void> {
  const { uid, operation, maxCalls, windowSeconds } = params;
  const firestore = getFirestore();
  // Coleção de topo, fora de `tenants/`: é infraestrutura, não dados de
  // negócio, e as Security Rules não a expõem a ninguém (o `match`
  // final nega tudo o que não está declarado; só o Admin SDK lhe toca).
  const ref = firestore.collection('_rateLimits').doc(`${uid}__${operation}`);

  try {
    await firestore.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const now = Date.now();
      const windowStart = snapshot.get('windowStart') as Timestamp | undefined;
      const count = (snapshot.get('count') as number | undefined) ?? 0;

      const elapsedSeconds = windowStart
        ? (now - windowStart.toMillis()) / 1000
        : Number.POSITIVE_INFINITY;

      if (elapsedSeconds >= windowSeconds) {
        tx.set(ref, {
          count: 1,
          windowStart: FieldValue.serverTimestamp(),
          operation,
          uid,
        });
        return;
      }

      if (count >= maxCalls) {
        throw new HttpsError(
          'resource-exhausted',
          'Demasiados pedidos em pouco tempo. Espera um momento e tenta ' +
            'outra vez.',
        );
      }

      tx.update(ref, { count: count + 1 });
    });
  } catch (error) {
    // O limite atingido é um `HttpsError` nosso e tem de subir; qualquer
    // outra falha é da infraestrutura do limitador — ver docstring.
    if (error instanceof HttpsError) throw error;
    return;
  }
}
