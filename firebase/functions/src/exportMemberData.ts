import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  // Ausente = "os meus dados". Um Gestor pode pedir os de outro membro
  // do seu tenant (é ele quem responde a um pedido de acesso por email
  // ou ao balcão).
  memberId: z.string().min(1).optional(),
});

/** Datas legíveis em vez de `{_seconds, _nanoseconds}`. */
function serialize(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([k, v]) => [
        k,
        serialize(v),
      ]),
    );
  }
  return value;
}

async function collectionToArray(
  ref: FirebaseFirestore.Query,
): Promise<unknown[]> {
  const snapshot = await ref.get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...(serialize(doc.data()) as object) }));
}

/**
 * Fase 11 (RGPD, artigo 15.º — direito de acesso; artigo 20.º —
 * portabilidade) — devolve TUDO o que a app guarda sobre um membro,
 * num formato que uma pessoa consegue ler e levar consigo.
 *
 * Sem paginação nem streaming: o volume por membro é pequeno (algumas
 * centenas de documentos no pior caso — anos de marcações) e o prazo
 * legal de resposta é de um mês, não de um segundo. Se um dia isto
 * crescer, o caminho é escrever para o Storage e devolver um link, não
 * paginar a resposta.
 *
 * Nota do que NÃO está aqui: os `fcmTokens` (identificadores técnicos
 * do dispositivo, sem valor para o titular e sensíveis se copiados) são
 * removidos, e a password nunca é conhecida por nós — o Firebase Auth
 * só guarda o hash.
 */
export const exportMemberData =
    onCall({ timeoutSeconds: 300 }, async (request) => {
  const caller = requireAuthenticated(request);
  // lê a app inteira de um membro; um pedido de RGPD é raro, cinco
  // em cinco minutos é folgado
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'exportMemberData',
    maxCalls: 5,
    windowSeconds: 300,
  });
  const { memberId } = parseInput(inputSchema, request.data ?? {});

  const targetId = memberId ?? caller.uid;
  const isSelf = targetId === caller.uid;
  const isManager = caller.roles.includes('manager');

  if (!isSelf && !isManager) {
    throw new HttpsError(
      'permission-denied',
      'Só podes exportar os teus próprios dados.',
    );
  }

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const memberRef = tenantRef.collection('members').doc(targetId);

  const memberSnapshot = await memberRef.get();
  if (!memberSnapshot.exists) {
    throw new HttpsError('not-found', 'Membro não encontrado neste ginásio.');
  }

  const profile = serialize(memberSnapshot.data()) as Record<string, unknown>;
  delete profile.fcmTokens;

  const [
    consentLog,
    assessments,
    loadHistory,
    planEntries,
    paymentRecords,
    subscriptions,
    usage,
    bookings,
    attendance,
  ] = await Promise.all([
    collectionToArray(memberRef.collection('consentLog')),
    collectionToArray(memberRef.collection('assessments')),
    collectionToArray(memberRef.collection('loadHistory')),
    collectionToArray(memberRef.collection('planEntries')),
    collectionToArray(memberRef.collection('paymentRecords')),
    collectionToArray(
      tenantRef.collection('subscriptions').where('memberId', '==', targetId),
    ),
    // `usage` não tem campo `memberId` — o id do documento é
    // `{memberId}_{serviceId}_{periodo}`. Um range no id apanha todos os
    // que começam pelo prefixo, sem precisar de índice novo.
    collectionToArray(
      tenantRef
        .collection('usage')
        .where('memberId', '==', targetId),
    ),
    // Marcações vivem espalhadas por subcoleções de cada ocorrência —
    // collection group é a única forma de as juntar. O filtro por
    // tenant vem de estarem todas debaixo deste `tenants/{id}`; o
    // `memberId` é o campo que as identifica.
    collectionToArray(
      firestore
        .collectionGroup('bookings')
        .where('memberId', '==', targetId),
    ),
    // Presenças e faltas. O `memberId` é campo desde a Fase 11 — sem
    // ele, um collection group query não os alcança (o id do documento
    // não serve para filtrar sem o caminho completo).
    collectionToArray(
      firestore
        .collectionGroup('attendance')
        .where('memberId', '==', targetId),
    ),
  ]);

  return {
    exportedAt: new Date().toISOString(),
    tenantId: caller.tenantId,
    memberId: targetId,
    profile,
    consentLog,
    assessments,
    loadHistory,
    planEntries,
    paymentRecords,
    subscriptions,
    usage,
    bookings,
    attendance,
  };
});
