import { getFirestore } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';

import { promoteFromWaitlist } from './lib/waitlist';

/**
 * Fase 11 (última ronda) — abrir mais vagas puxa a lista de espera.
 *
 * A promoção automática vivia só no cancelamento. Mas o caso mais
 * comum num estúdio nem é esse: a aula enche, ficam três pessoas à
 * espera, e o instrutor decide "cabem mais dois". Editava a lotação de
 * 8 para 10 — e os dois lugares novos ficavam vazios com três pessoas
 * na fila a olhar para eles, porque nada os ia buscar.
 *
 * Um trigger e não uma Cloud Function chamada pela app: editar a
 * sessão é uma escrita direta do cliente (as Security Rules
 * permitem-na desde a Fase 6), e há mais do que um caminho até lá.
 * Reagir ao documento cobre todos, incluindo uma correção feita à mão
 * na consola.
 *
 * Só reage a **aumentos** de lotação. Reduzir vagas passa por
 * `removeMembersFromOccurrence`, que já trata da fila à sua maneira.
 */
export const onOccurrenceCapacityChanged = onDocumentUpdated(
  'tenants/{tenantId}/sessionOccurrences/{occurrenceId}',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const previousCapacity = (before.get('capacity') as number) ?? 0;
    const currentCapacity = (after.get('capacity') as number) ?? 0;
    if (currentCapacity <= previousCapacity) return;
    if ((after.get('status') as string) !== 'scheduled') return;

    // Sessão que já começou não interessa a ninguém na fila.
    const startAt = after.get('startAt') as FirebaseFirestore.Timestamp | null;
    if (startAt && startAt.toDate() < new Date()) return;

    const firestore = getFirestore();
    const tenantRef = firestore
      .collection('tenants')
      .doc(event.params.tenantId);

    // `promoteFromWaitlist` volta a ler a lotação e as marcações
    // ativas — o número de lugares abertos aqui é só o teto de quantas
    // pessoas faz sentido tentar promover nesta passagem.
    const result = await promoteFromWaitlist({
      tenantRef,
      occurrenceId: event.params.occurrenceId,
      maxPromotions: currentCapacity - previousCapacity,
    });

    if (result.promotedMemberIds.length > 0) {
      console.log(
        'onOccurrenceCapacityChanged',
        event.params.occurrenceId,
        'promovidos:',
        result.promotedMemberIds.length,
      );
    }
  },
);
