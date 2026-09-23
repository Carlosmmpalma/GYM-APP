import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  memberId: z.string().min(1),
  planId: z.string().min(1),
  agreedPrice: z.number().nonnegative(),
  currency: z.string().min(1),
});

/**
 * Atribui O plano de um membro. **Um plano ativo por membro.**
 *
 * ## Como era, e porque mudou
 *
 * Um membro podia ter várias subscriptions ativas, e isso obrigava a
 * duas regras de conflito: "não podes ter duas que dêem o MESMO
 * serviço" e, desde a Fase 8, "não podes ter duas que dêem serviços do
 * mesmo `exclusiveGroup`" — uma etiqueta que o Gestor tinha de escrever
 * à mão, em texto livre, no ecrã dos serviços.
 *
 * Nenhuma das duas era compreensível de fora. O ecrã de atribuir
 * partia-se em duas secções ("níveis" em escolha única, "avulsos" em
 * escolha múltipla) sem nunca dizer porquê, e um plano ia parar a uma
 * ou a outra consoante os serviços que embrulhasse — o "Hyrox Team"
 * aparecia como um nível de acompanhamento porque, lá dentro, incluía
 * "Treino livre".
 *
 * Um plano por membro apaga as duas regras de uma vez, e não por
 * simplificação cosmética:
 *
 * - Não há dois planos a dar o mesmo serviço, logo não há conflito.
 * - Não há dois planos a dar serviços alternativos, logo não há
 *   `exclusiveGroup`.
 * - E o limite semanal deixa de ser ambíguo. `resolveEligibility` (ver
 *   `lib/bookingLogic.ts`) resolvia-o apanhando a PRIMEIRA subscription
 *   que desse aquele serviço — com dois planos a darem-no com limites
 *   diferentes, o limite aplicado era o que a base de dados calhasse
 *   devolver primeiro. Com um plano só não há nada para escolher.
 *
 * A proteção que interessa passou para onde se entende sem explicação:
 * ao MARCAR (ver `createBooking.ts`), onde ninguém pode estar em dois
 * sítios à mesma hora.
 *
 * ## Substitui em vez de recusar
 *
 * Dar um plano a quem já tem um cancela o anterior, na mesma escrita
 * atómica. Recusar obrigaria a dois passos ("vai cancelar primeiro")
 * para o que é um só gesto na cabeça de quem o faz — mudar de plano.
 *
 * As marcações já feitas NÃO são tocadas: foram aceites ao abrigo do
 * plano que estava em vigor nessa altura, e apagá-las retroativamente
 * seria reescrever o passado. O ecrã avisa quais ficam descobertas
 * daqui para a frente.
 *
 * Só um Gestor do próprio tenant pode chamar isto (requireManager).
 */
export const createSubscription = onCall(async (request) => {
  const caller = requireManager(request);

  const { memberId, planId, agreedPrice, currency } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  const memberSnap = await tenantRef.collection('members').doc(memberId).get();
  if (!memberSnap.exists) {
    throw new HttpsError('not-found', 'Membro não encontrado neste tenant.');
  }

  const planRef = tenantRef.collection('plans').doc(planId);
  const planSnap = await planRef.get();
  if (!planSnap.exists) {
    throw new HttpsError('not-found', 'Plano não encontrado neste tenant.');
  }
  if (planSnap.data()?.active === false) {
    throw new HttpsError('failed-precondition', 'Este plano já não está ativo.');
  }

  // Domain Model v1 §12 — os serviços concedidos por este Plan.
  const planServicesSnap = await planRef
    .collection('services')
    .where('enabled', '==', true)
    .get();
  const grantedServiceIds = planServicesSnap.docs.map((doc) => doc.id);

  if (grantedServiceIds.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'Este plano ainda não tem nenhum serviço associado.',
    );
  }

  // O plano em vigor, se houver. Normalmente zero ou um; a query é
  // uma lista porque dados antigos (de quando vários eram permitidos)
  // podem trazer mais, e cancelá-los todos é o comportamento certo.
  const existingActiveSnap = await tenantRef
    .collection('subscriptions')
    .where('memberId', '==', memberId)
    .where('status', '==', 'active')
    .get();

  const replaced: string[] = [];
  const planNameById = new Map<string, string>();
  for (const doc of existingActiveSnap.docs) {
    const anteriorPlanId = doc.data().planId as string;
    if (!planNameById.has(anteriorPlanId)) {
      const anteriorSnap = await tenantRef
        .collection('plans')
        .doc(anteriorPlanId)
        .get();
      planNameById.set(
        anteriorPlanId,
        (anteriorSnap.data()?.name as string | undefined) ?? anteriorPlanId,
      );
    }
    replaced.push(planNameById.get(anteriorPlanId)!);
  }

  // Cancelar o anterior e criar o novo numa escrita só: um erro a meio
  // deixaria o membro sem plano nenhum ou com dois.
  const batch = getFirestore().batch();
  for (const doc of existingActiveSnap.docs) {
    batch.update(doc.ref, {
      status: 'cancelled',
      endDate: FieldValue.serverTimestamp(),
      cancelledBy: caller.uid,
      cancelledReason: 'replaced',
    });
  }

  const subscriptionRef = tenantRef.collection('subscriptions').doc();
  batch.set(subscriptionRef, {
    memberId,
    planId,
    status: 'active',
    startDate: FieldValue.serverTimestamp(),
    endDate: null,
    agreedPrice,
    currency,
    activeServiceIds: grantedServiceIds,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: caller.uid,
  });
  await batch.commit();

  // `replaced` deixa o ecrã dizer "substituiu X" em vez de só
  // "atribuído" — quem muda um plano quer confirmação de que o
  // anterior saiu.
  return { subscriptionId: subscriptionRef.id, replaced };
});
