import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManagerOrInstructor } from './lib/callerContext';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  seriesId: z.string().min(1),
  memberIds: z.array(z.string().min(1)).min(1),
  isExtra: z.boolean().optional().default(false),
});

/**
 * Atribuir alunos a uma série inteira — "todas as semanas", e não só
 * àquela aula.
 *
 * ## O que faltava
 *
 * A série já tinha `preAssignedMemberIds`, e a geração semanal já os
 * usava: cada ocorrência nova nasce com essas pessoas marcadas, com as
 * mesmas validações de um booking normal (ver
 * `generateRecurringOccurrences.ts`). O que não existia era forma de
 * ESCREVER nessa lista pela app — o "Adicionar membro", tanto no
 * detalhe da aula como no da série, chamava sempre
 * `assignMembersToOccurrence` e atingia uma única data.
 *
 * Resultado prático: quem inscrevia um aluno numa aula semanal tinha
 * de repetir o gesto semana a semana, e nas semanas ainda não geradas
 * não tinha sequer onde o fazer.
 *
 * ## As duas metades
 *
 * **O futuro por gerar** resolve-se com a lista: entrar em
 * `preAssignedMemberIds` basta para a geração os marcar daí em diante.
 *
 * **As ocorrências JÁ geradas** não são tocadas por essa lista — já
 * existem. Por isso são percorridas aqui, uma a uma, com o mesmo
 * `resolveEligibility` + `runBookingTransaction` que a geração usa. Ou
 * seja: a capacidade da sala, a elegibilidade do plano e o limite
 * semanal continuam todos a valer, aula a aula.
 *
 * ## Falhar numa semana não é falhar no pedido
 *
 * Mesmo princípio da geração e do `assignMembersToOccurrence`: uma
 * aula cheia, ou uma semana em que o aluno já gastou o limite, não
 * pode impedir as restantes. Cada tentativa é isolada e o que correu
 * mal volta na contagem, para o ecrã poder dizer "marcado em 6 das 8
 * semanas" em vez de um erro só.
 *
 * Isto é deliberado e não um atalho: um aluno com 2 sessões por semana
 * que entre numa série de 3 dias vai mesmo esbarrar no limite à
 * terceira, e isso é o sistema a funcionar. O que não pode é a
 * terceira semana estragar as duas primeiras.
 */
export const assignMembersToSeries = onCall({ timeoutSeconds: 120 }, async (request) => {
  const caller = requireManagerOrInstructor(request);
  const { seriesId, memberIds, isExtra } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const seriesRef = tenantRef.collection('sessionSeries').doc(seriesId);

  const seriesSnap = await seriesRef.get();
  if (!seriesSnap.exists) {
    throw new HttpsError('not-found', 'Esta série já não existe.');
  }
  if ((seriesSnap.get('status') as string | undefined) === 'cancelled') {
    throw new HttpsError(
      'failed-precondition',
      'Esta série está cancelada. Não há semanas futuras para marcar.',
    );
  }

  const serviceId = seriesSnap.get('serviceId') as string;

  // A lista primeiro. Se o passo seguinte falhar a meio, as semanas que
  // ainda não existem ficam na mesma garantidas — ao contrário: marcar
  // as geradas e não entrar na lista dava um aluno que desaparecia do
  // horário assim que o cron gerasse a semana seguinte.
  await seriesRef.update({
    preAssignedMemberIds: FieldValue.arrayUnion(...memberIds),
  });

  const agora = new Date();
  const futurasSnap = await tenantRef
    .collection('sessionOccurrences')
    .where('seriesId', '==', seriesId)
    .where('startAt', '>=', agora)
    .get();
  const futuras = futurasSnap.docs.filter(
    (doc) => (doc.data().status as string | undefined) === 'scheduled',
  );

  // Por membro, para o ecrã poder dizer quem ficou de fora e não só
  // quantos — "a Rita ficou sem vaga em 2 semanas" é acionável, "2
  // falhas" não é.
  const resultados: Record<string, { assigned: number; skipped: number }> = {};

  for (const memberId of memberIds) {
    const contagem = { assigned: 0, skipped: 0 };
    const eligibility = await resolveEligibility(tenantRef, memberId, serviceId);

    if (!eligibility) {
      // Sem plano que cubra este serviço: nenhuma semana vai dar, e
      // percorrê-las todas só para confirmar é desperdício.
      contagem.skipped = futuras.length;
      resultados[memberId] = contagem;
      continue;
    }

    for (const occDoc of futuras) {
      const startAt = (occDoc.get('startAt') as FirebaseFirestore.Timestamp).toDate();
      const result = await runBookingTransaction(firestore, {
        tenantRef,
        occurrenceRef: occDoc.ref,
        bookingRef: occDoc.ref.collection('bookings').doc(memberId),
        memberId,
        serviceId,
        startAt,
        source: 'manager',
        eligibility,
        isExtra,
      });
      if (result.kind === 'booked') contagem.assigned += 1;
      else contagem.skipped += 1;
    }

    resultados[memberId] = contagem;
  }

  return {
    occurrences: futuras.length,
    results: resultados,
  };
});
