import { getAuth } from 'firebase-admin/auth';
import {
  getFirestore,
  FieldValue,
  Query,
  DocumentReference,
} from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  memberId: z.string().min(1),
  // Salvaguarda deliberada contra o clique errado: quem chama tem de
  // repetir o número de sócio. Isto é irreversível e não há "desfazer".
  confirmMemberNumber: z.string().min(1),
});

/** Apaga uma query inteira em lotes (o batch do Firestore vai até 500). */
async function deleteQuery(query: Query): Promise<number> {
  const firestore = getFirestore();
  let deleted = 0;
  for (;;) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) return deleted;
    const batch = firestore.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snapshot.size;
    // Menos do que o limite = era a última página.
    if (snapshot.size < 400) return deleted;
  }
}

async function deleteSubcollection(
  memberRef: DocumentReference,
  name: string,
): Promise<number> {
  return deleteQuery(memberRef.collection(name));
}

/**
 * Fase 11 (RGPD, artigo 17.º — direito ao apagamento).
 *
 * Manager-only, e não self-service: o artigo 12.º, n.º 6 permite pedir
 * prova de identidade antes de apagar, e um botão "apagar a minha
 * conta" dentro da app não a consegue verificar melhor do que uma
 * sessão iniciada — que pode ser um telemóvel deixado desbloqueado. Um
 * pedido de apagamento passa pelo estúdio, que confirma quem é a
 * pessoa; a app dá-lhe a ferramenta.
 *
 * **O que é apagado mesmo**: perfil, consentimentos, avaliações,
 * histórico de carga, plano de treino, marcações, presenças, utilização
 * semanal, subscrições, e a conta no Firebase Auth.
 *
 * **O que NÃO é apagado, e porquê**: os `paymentRecords`. O artigo
 * 17.º, n.º 3, alínea b) excetua o tratamento necessário ao
 * cumprimento de uma obrigação legal — e em Portugal os documentos de
 * suporte à contabilidade têm retenção obrigatória (10 anos, artigo
 * 123.º do CIRC). Apagá-los a pedido do titular seria trocar uma
 * infração por outra. O que se faz é **anonimizar**: o registo
 * financeiro fica, deixa de estar ligado a uma pessoa identificável.
 * É a resposta que o RGPD espera aqui, e é por isso que esta função
 * devolve a contagem separada — para o Gestor poder dizer ao titular
 * exatamente o que ficou.
 */
export const deleteMemberData =
    onCall({ timeoutSeconds: 300 }, async (request) => {
  const caller = requireManager(request);
  // irreversível e caro — nunca é uma operação repetida
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'deleteMemberData',
    maxCalls: 5,
    windowSeconds: 300,
  });
  const { memberId, confirmMemberNumber } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const memberRef = tenantRef.collection('members').doc(memberId);

  const snapshot = await memberRef.get();
  if (!snapshot.exists) {
    throw new HttpsError('not-found', 'Membro não encontrado neste ginásio.');
  }

  const memberNumber = snapshot.get('memberNumber') as string | undefined;
  if (memberNumber !== confirmMemberNumber) {
    throw new HttpsError(
      'failed-precondition',
      'O número de sócio de confirmação não corresponde a este membro.',
    );
  }

  // Dados de saúde e de treino — apagados sem reservas.
  const assessments = await deleteSubcollection(memberRef, 'assessments');
  const loadHistory = await deleteSubcollection(memberRef, 'loadHistory');
  const planEntries = await deleteSubcollection(memberRef, 'planEntries');
  const consentLog = await deleteSubcollection(memberRef, 'consentLog');

  // Marcações (aulas e treino livre) e presenças, espalhadas por
  // subcoleções de cada ocorrência/slot.
  const bookings = await deleteQuery(
    firestore.collectionGroup('bookings').where('memberId', '==', memberId),
  );
  const attendance = await deleteQuery(
    firestore
      .collectionGroup('attendance')
      .where('memberId', '==', memberId),
  );

  const usage = await deleteQuery(
    tenantRef.collection('usage').where('memberId', '==', memberId),
  );
  const subscriptions = await deleteQuery(
    tenantRef.collection('subscriptions').where('memberId', '==', memberId),
  );

  // Retenção fiscal — ver docstring. Fica o valor e o período; sai tudo
  // o que liga o registo a uma pessoa.
  const paymentSnapshot = await memberRef.collection('paymentRecords').get();
  if (!paymentSnapshot.empty) {
    const batch = firestore.batch();
    paymentSnapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        anonymizedAt: FieldValue.serverTimestamp(),
        anonymizedBy: caller.uid,
        memberName: FieldValue.delete(),
        memberNumber: FieldValue.delete(),
      });
    });
    await batch.commit();
  }

  // O documento do membro em si passa a ser só a casca que segura os
  // `paymentRecords` retidos — sem nome, contactos, NIF, morada,
  // contacto de emergência nem consentimentos.
  await memberRef.set(
    {
      status: 'deleted',
      anonymizedAt: FieldValue.serverTimestamp(),
      anonymizedBy: caller.uid,
      name: 'Membro eliminado',
      memberNumber: FieldValue.delete(),
      phone: FieldValue.delete(),
      email: FieldValue.delete(),
      birthDate: FieldValue.delete(),
      address: FieldValue.delete(),
      nif: FieldValue.delete(),
      emergencyContact: FieldValue.delete(),
      consent: FieldValue.delete(),
      fcmTokens: FieldValue.delete(),
      currentPaymentStatus: FieldValue.delete(),
      currentPaymentPeriod: FieldValue.delete(),
    },
    { merge: true },
  );

  // Último passo: a identidade. Depois disto o membro não consegue
  // autenticar-se. Fica no fim para que uma falha a meio não deixe uma
  // conta capaz de entrar numa app sem o seu perfil.
  await getAuth()
    .deleteUser(memberId)
    .catch(() => undefined);

  return {
    deleted: {
      assessments,
      loadHistory,
      planEntries,
      consentLog,
      bookings,
      attendance,
      usage,
      subscriptions,
    },
    // Não apagados por obrigação legal de retenção — ver docstring.
    anonymizedPaymentRecords: paymentSnapshot.size,
  };
});
