import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  privacyPolicyVersion: z.number().int().positive(),
  healthDataGranted: z.boolean(),
});

/**
 * Fase 11 (RGPD, artigo 7.º) — regista o consentimento do PRÓPRIO
 * utilizador autenticado.
 *
 * Porquê uma Cloud Function e não uma escrita direta com as Security
 * Rules a permitir o campo `consent`: o artigo 7.º, n.º 1 exige que o
 * responsável pelo tratamento consiga **demonstrar** que o titular
 * consentiu. Um campo escrito pelo cliente, com um timestamp escolhido
 * pelo cliente, não demonstra nada — reescreve-se à vontade. Aqui o
 * `serverTimestamp()` e o `uid` vêm do servidor, e as Rules mantêm
 * `consent` fora do que o cliente pode escrever.
 *
 * O histórico fica em `members/{uid}/consentLog` além do estado atual
 * no documento: a prova que interessa a uma autoridade é "consentiu em
 * X, retirou em Y", não só o valor de hoje. É append-only.
 *
 * Só membros: staff não tem dados de saúde tratados pela app, e a sua
 * relação com o ginásio é laboral, não de cliente.
 */
export const recordConsent = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  // escrita pequena, mas append-only no consentLog — sem limite,
  // um ciclo enche a subcoleção
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'recordConsent',
    maxCalls: 20,
    windowSeconds: 300,
  });
  const { privacyPolicyVersion, healthDataGranted } = parseInput(inputSchema, 
    request.data,
  );

  const firestore = getFirestore();
  const memberRef = firestore
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('members')
    .doc(caller.uid);

  const snapshot = await memberRef.get();
  if (!snapshot.exists) {
    // Staff a chamar isto, ou uma conta órfã. Não é erro do utilizador,
    // mas também não há onde registar — devolver `ok: false` deixa o
    // cliente seguir em frente sem tratar isto como falha.
    return { recorded: false };
  }

  const now = FieldValue.serverTimestamp();

  await firestore.runTransaction(async (tx) => {
    tx.set(
      memberRef,
      {
        consent: {
          privacyPolicyVersion,
          acceptedAt: now,
          healthDataGranted,
          healthDataUpdatedAt: now,
        },
      },
      { merge: true },
    );
    tx.set(memberRef.collection('consentLog').doc(), {
      privacyPolicyVersion,
      healthDataGranted,
      recordedAt: now,
      // Quem estava autenticado quando isto foi registado. É sempre o
      // próprio (a função não aceita `memberId`), mas fica explícito no
      // registo em vez de implícito no caminho do documento.
      recordedBy: caller.uid,
    });
  });

  return { recorded: true };
});
