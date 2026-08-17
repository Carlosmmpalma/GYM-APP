import { getMessaging } from 'firebase-admin/messaging';

/**
 * Fase 8 (auditoria funcional, UC11/UC18/UC24 fechados) — extraído de
 * `sendNotification.ts`, que até aqui era o ÚNICO caminho que enviava
 * push e exigia sempre um humano a escrever título/corpo.
 *
 * Os use cases fechados pedem notificação AUTOMÁTICA quando é o
 * estúdio a mexer na marcação de alguém:
 *   * UC18 — "os alunos removidos são notificados (UC11)";
 *   * UC10/UC18 — cancelamento de aula pelo estúdio;
 *   * UC24 — desativar instrutor: "alunos notificados e sessões
 *     devolvidas ao limite semanal";
 *   * UC19 — "sistema cria o horário e notifica os alunos já
 *     associados".
 *
 * Nunca lança: uma notificação que falha (sem tokens, VAPID key por
 * configurar, token expirado) NUNCA pode desfazer nem bloquear a
 * operação de negócio que a originou — o cancelamento já aconteceu e
 * está correto mesmo que o aviso não saia. Devolve quantas mensagens
 * saíram, para quem quiser registar/devolver ao cliente.
 */
export async function notifyMembers(
  tenantRef: FirebaseFirestore.DocumentReference,
  memberIds: string[],
  title: string,
  body: string,
): Promise<{ sent: number; targets: number }> {
  const uniqueIds = [...new Set(memberIds)];
  if (uniqueIds.length === 0) return { sent: 0, targets: 0 };

  try {
    const memberDocs = await tenantRef.firestore.getAll(
      ...uniqueIds.map((id) => tenantRef.collection('members').doc(id)),
    );
    const tokens = [
      ...new Set(
        memberDocs.flatMap((doc) => (doc.data()?.fcmTokens as string[] | undefined) ?? []),
      ),
    ];
    if (tokens.length === 0) return { sent: 0, targets: uniqueIds.length };

    const result = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
    });
    return { sent: result.successCount, targets: uniqueIds.length };
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[notifyMembers] falhou o envio, operação de negócio mantém-se:', err);
    return { sent: 0, targets: uniqueIds.length };
  }
}

/**
 * Descrição curta de uma sessão para o corpo da notificação
 * automática — só DIA/MÊS, deliberadamente **sem horas**.
 *
 * O runtime das Functions não sabe o fuso do dispositivo do aluno e
 * não há biblioteca de timezone nas dependências (mesma limitação já
 * assinalada em `lib/isoWeek.ts`, onde é inofensiva porque só afeta a
 * fronteira da semana). Aqui NÃO seria inofensiva: `Europe/Lisbon` é
 * UTC+1 no horário de verão, por isso imprimir a hora em UTC dava uma
 * notificação com a hora ERRADA metade do ano — pior do que não a ter.
 * O dia/mês mantém-se correto para qualquer sessão em horário normal
 * de ginásio (06:00-22:00 locais nunca saltam de dia com um desvio de
 * 1h), e a hora exata está no ecrã da app, a um toque de distância.
 */
export function describeOccurrence(startAt: Date): string {
  const dd = startAt.getUTCDate().toString().padStart(2, '0');
  const mm = (startAt.getUTCMonth() + 1).toString().padStart(2, '0');
  return `${dd}/${mm}`;
}
