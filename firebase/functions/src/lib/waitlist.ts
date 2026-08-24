import { getFirestore } from 'firebase-admin/firestore';

import { notifyMembers, describeOccurrence } from './notifications';
import { resolveEligibility, runBookingTransaction } from './bookingLogic';

/**
 * Fase 11 — lista de espera de uma sessão cheia.
 *
 * A aplicação impõe capacidade por desenho, portanto aulas cheias são o
 * normal e não a exceção. Sem lista de espera, um cancelamento deixava
 * **um lugar vazio que ninguém sabia que existia**: o aluno interessado
 * tinha de andar a abrir a app a ver se tinha vagado, e na maior parte
 * das vezes não voltava a abrir.
 *
 * Vive em `sessionOccurrences/{id}/waitlist/{memberId}`, com o instante
 * de entrada a definir a ordem. O id do documento é o `memberId` para
 * tornar impossível entrar duas vezes na mesma fila.
 */

/**
 * Promove o primeiro da fila quando um lugar vaga.
 *
 * **Promoção automática, não convite.** A alternativa — avisar e dar X
 * minutos para confirmar — é o que algumas apps fazem, mas exige um
 * temporizador por lugar vago e deixa o lugar em suspenso enquanto
 * ninguém responde. Num estúdio pequeno isso significa aulas a começar
 * com lugares vazios reservados para quem não viu a notificação.
 *
 * A troca é justa porque cancelar é barato: quem for promovido e já não
 * puder vir cancela, e — dentro da janela de antecedência — recupera a
 * utilização semanal. O aviso diz-lhe exatamente isso.
 *
 * Nunca lança. É chamada a seguir a um cancelamento já concluído; se a
 * promoção falhar, o cancelamento não pode ser desfeito por causa
 * disso — fica um lugar por preencher, que é o estado anterior a esta
 * funcionalidade existir.
 */
export async function promoteFromWaitlist(params: {
  tenantRef: FirebaseFirestore.DocumentReference;
  occurrenceId: string;
  /**
   * Quantos lugares há para preencher. Um cancelamento liberta um; o
   * estúdio a aumentar a lotação de 8 para 12 liberta quatro, e sem
   * isto ficavam três pessoas na fila a olhar para vagas livres.
   */
  maxPromotions?: number;
}): Promise<{ promotedMemberIds: string[] }> {
  const { tenantRef, occurrenceId } = params;
  const maxPromotions = Math.max(1, params.maxPromotions ?? 1);
  const firestore = getFirestore();
  const occurrenceRef = tenantRef
    .collection('sessionOccurrences')
    .doc(occurrenceId);

  const promoted: string[] = [];

  try {
    const occurrenceSnap = await occurrenceRef.get();
    if (!occurrenceSnap.exists) return { promotedMemberIds: promoted };
    if ((occurrenceSnap.get('status') as string) !== 'scheduled') {
      return { promotedMemberIds: promoted };
    }

    const capacity = (occurrenceSnap.get('capacity') as number) ?? 0;
    const active = (occurrenceSnap.get('activeBookingCount') as number) ?? 0;
    // Quantos cabem mesmo: o pedido nunca pode encher a sala acima da
    // lotação, mesmo que peça mais.
    const room = Math.min(maxPromotions, Math.max(0, capacity - active));
    if (room === 0) return { promotedMemberIds: promoted };

    const serviceId = occurrenceSnap.get('serviceId') as string | undefined;
    if (!serviceId) return { promotedMemberIds: promoted };

    // Por ordem de chegada. Percorre-se em vez de levar só o primeiro:
    // quem estava na fila pode ter perdido a elegibilidade entretanto
    // (plano acabou, foi cancelado), e nesse caso passa ao seguinte em
    // vez de o lugar ficar por preencher.
    const queue = await occurrenceRef
      .collection('waitlist')
      .orderBy('joinedAt')
      .limit(room + 10)
      .get();

    for (const entry of queue.docs) {
      const memberId = entry.id;
      const eligibility = await resolveEligibility(
        tenantRef,
        memberId,
        serviceId,
      );
      if (!eligibility) {
        // Já não tem direito: sai da fila em silêncio. Mantê-lo seria
        // bloquear a promoção de quem vem a seguir, para sempre.
        await entry.ref.delete().catch(() => undefined);
        continue;
      }

      const startAt = (
        occurrenceSnap.get('startAt') as FirebaseFirestore.Timestamp
      ).toDate();

      try {
        await runBookingTransaction(firestore, {
          tenantRef,
          occurrenceRef,
          bookingRef: occurrenceRef.collection('bookings').doc(memberId),
          memberId,
          serviceId,
          startAt,
          source: 'waitlist',
          isExtra: false,
          eligibility,
        });
      } catch (error) {
        // Ficou cheia outra vez, ou o membro já lá estava. Não é erro
        // nosso — desiste e deixa o lugar para o próximo cancelamento.
        break;
      }

      await entry.ref.delete().catch(() => undefined);

      await notifyMembers(
        tenantRef,
        [memberId],
        'Entraste na aula!',
        `Vagou um lugar na sessão de ${describeOccurrence(startAt)} e a tua ` +
          'marcação foi feita automaticamente. Se já não puderes vir, ' +
          'cancela na app.',
      );

      promoted.push(memberId);
      if (promoted.length >= room) break;
    }

    // Uma vez no fim, e não a cada promoção: renumerar é uma escrita
    // por pessoa na fila, e a ordem verdadeira (`joinedAt`) nunca
    // depende destes números.
    await renumberWaitlist(occurrenceRef);
  } catch (error) {
    // Ver docstring: uma falha aqui não desfaz o cancelamento.
    return { promotedMemberIds: promoted };
  }

  return { promotedMemberIds: promoted };
}

/**
 * Reescreve a posição de cada pessoa na fila e o total na ocorrência.
 *
 * As Security Rules deixam um aluno ler **a sua própria** entrada, mas
 * não listar a fila — quem está à espera é informação dos outros. Sem
 * isto, a app só poderia dizer "estás na lista", que não chega para
 * decidir se vale a pena continuar à espera ou procurar outra aula.
 *
 * Por isso a posição é escrita no documento de cada um, e recalculada
 * a cada entrada, saída e promoção. São N escritas por alteração, com
 * N = tamanho da fila; num estúdio isso é uma mão-cheia de documentos,
 * e a alternativa (o cliente contar quem está à frente) obrigava a
 * abrir a fila inteira à leitura.
 */
export async function renumberWaitlist(
  occurrenceRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  try {
    const queue = await occurrenceRef
      .collection('waitlist')
      .orderBy('joinedAt')
      .get();

    const batch = getFirestore().batch();
    queue.docs.forEach((doc, index) => {
      if (doc.get('position') !== index + 1) {
        batch.update(doc.ref, { position: index + 1 });
      }
    });
    batch.update(occurrenceRef, { waitlistCount: queue.size });
    await batch.commit();
  } catch (error) {
    // Cosmético: a fila continua correta (a ordem verdadeira é
    // `joinedAt`), só o número mostrado pode ficar desatualizado até à
    // alteração seguinte. Não vale desfazer uma marcação por isto.
  }
}
