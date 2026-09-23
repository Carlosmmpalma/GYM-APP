import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Recusa marcar duas coisas que se cruzem no tempo.
 *
 * ## Porque isto passou a existir
 *
 * A app impedia o que não devia e não impedia o que devia. Havia uma
 * regra inventada — o `exclusiveGroup` dos serviços, que obrigava o
 * Gestor a declarar quais é que eram "alternativas" uns dos outros — e
 * não havia **nenhuma** verificação de horários. Um aluno podia marcar
 * duas aulas exatamente à mesma hora, todos os dias, e nada o travava.
 *
 * A regra artificial saiu. Esta ficou no lugar dela, e é a única que
 * não precisa de explicação nenhuma: ninguém está em dois sítios ao
 * mesmo tempo.
 *
 * ## Como encontra os candidatos
 *
 * Uma marcação guarda a `startAt` copiada da sessão, mas não a hora de
 * fim. Em vez de assumir uma duração (que produziria recusas erradas
 * nos dois sentidos), lê a sessão de cada candidata — que é o pai do
 * documento da marcação, tanto nas aulas
 * (`sessionOccurrences/{id}/bookings/{membro}`) como no treino livre
 * (`freeTrainingSchedules/{semana}/slots/{id}/bookings/{membro}`).
 *
 * A janela de busca é o intervalo da sessão nova alargado por
 * [JANELA_HORAS] para trás, para apanhar uma marcação que COMEÇOU antes
 * e ainda está a decorrer. Sem essa folga, marcar às 10h00 não via a
 * aula das 09h30 que só acaba às 10h30.
 *
 * São poucos documentos: as marcações de um membro num intervalo de
 * poucas horas contam-se pelos dedos.
 */
const JANELA_HORAS = 6;

export interface SessaoSobreposta {
  /** Nome legível, para a mensagem. */
  titulo: string;
  inicio: Date;
}

/**
 * @param excluirOccurrenceId a sessão que se está a marcar — as suas
 *   próprias marcações nunca contam como conflito consigo mesma.
 */
export async function encontrarSobreposicao(
  firestore: FirebaseFirestore.Firestore,
  tenantRef: FirebaseFirestore.DocumentReference,
  opcoes: {
    memberId: string;
    inicio: Date;
    fim: Date;
    excluirOccurrenceId: string;
  },
): Promise<SessaoSobreposta | null> {
  const { memberId, inicio, fim, excluirOccurrenceId } = opcoes;

  const janelaInicio = new Date(inicio.getTime() - JANELA_HORAS * 3600_000);

  const candidatas = await firestore
    .collectionGroup('bookings')
    .where('memberId', '==', memberId)
    .where('status', '==', 'booked')
    .where('startAt', '>=', Timestamp.fromDate(janelaInicio))
    .where('startAt', '<', Timestamp.fromDate(fim))
    .get();

  for (const doc of candidatas.docs) {
    const sessaoRef = doc.ref.parent.parent;
    if (!sessaoRef || sessaoRef.id === excluirOccurrenceId) continue;

    // Marcações de OUTRO tenant nunca podem aparecer aqui: uma
    // collection group query varre o projeto todo, e o `memberId` é um
    // uid — único entre tenants — mas confirmar o caminho custa nada e
    // fecha a porta a um id reaproveitado.
    if (!sessaoRef.path.startsWith(tenantRef.path)) continue;

    const sessaoSnap = await sessaoRef.get();
    if (!sessaoSnap.exists) continue;
    const dados = sessaoSnap.data()!;
    if (dados.status === 'cancelled') continue;

    const outroInicio = (dados.startAt as Timestamp | undefined)?.toDate();
    const outroFim = (dados.endAt as Timestamp | undefined)?.toDate();
    if (!outroInicio || !outroFim) continue;

    // Dois intervalos cruzam-se se cada um começa antes de o outro
    // acabar. Fronteiras EXCLUSIVAS: uma aula que acaba às 10h00 e
    // outra que começa às 10h00 não se sobrepõem — é o encadeamento
    // normal de quem faz duas aulas seguidas, e recusá-lo seria a
    // regra a atrapalhar em vez de proteger.
    if (outroInicio < fim && inicio < outroFim) {
      return {
        titulo: (dados.title as string | undefined) ?? 'outra marcação',
        inicio: outroInicio,
      };
    }
  }

  return null;
}

/** A recusa, com a hora da outra sessão para a pessoa a reconhecer. */
export function erroDeSobreposicao(outra: SessaoSobreposta): HttpsError {
  const hora = outra.inicio.toLocaleTimeString('pt-PT', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Europe/Lisbon',
  });
  return new HttpsError(
    'failed-precondition',
    `Já tens uma marcação às ${hora} que se cruza com esta. ` +
      'Cancela essa primeiro.',
    { reason: 'overlap', otherStartAt: outra.inicio.toISOString() },
  );
}
