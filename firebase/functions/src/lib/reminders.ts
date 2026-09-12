import { FieldValue } from 'firebase-admin/firestore';

import { notifyMembers } from './notifications';

/**
 * Fase 11 — lembrete antes da aula.
 *
 * A falta sem aviso é o custo real de um estúdio com capacidade
 * limitada: o lugar ficou ocupado, ninguém o pôde usar, e a aula
 * correu com menos gente do que a lista dizia. Quase sempre não é
 * má-fé — é alguém que marcou na segunda-feira e se esqueceu na
 * quinta.
 *
 * O lembrete resolve os dois lados de uma vez: quem vem confirma
 * mentalmente, e quem já não pode vir tem ali o empurrão para cancelar
 * a tempo — o que devolve a utilização semanal (dentro da janela) e
 * liberta o lugar para o primeiro da lista de espera.
 *
 * Por isso o corpo da mensagem diz explicitamente "se não puderes vir,
 * cancela": o objetivo não é só recordar, é provocar o cancelamento
 * atempado.
 */

/** Sem configuração, avisa na véspera/manhã do próprio dia. */
const DEFAULT_REMINDER_HOURS = 12;

export async function sendSessionRemindersForTenant(params: {
  tenantRef: FirebaseFirestore.DocumentReference;
  now?: Date;
}): Promise<{ occurrences: number; notified: number }> {
  const { tenantRef } = params;
  const now = params.now ?? new Date();

  const policySnap = await tenantRef
    .collection('config')
    .doc('notificationPolicy')
    .get();
  if (policySnap.exists && policySnap.get('sessionRemindersEnabled') === false) {
    return { occurrences: 0, notified: 0 };
  }
  const hours =
    (policySnap.get('sessionReminderHours') as number | undefined) ??
    DEFAULT_REMINDER_HOURS;

  const horizon = new Date(now.getTime() + hours * 3600_000);

  // Só sessões que ainda não começaram, caem dentro da janela, e ainda
  // não foram avisadas.
  //
  // O `reminderSentAt == null` não é cosmético. A função corre de hora
  // a hora com uma janela de doze, portanto a MESMA aula entra na
  // janela doze vezes; antes eram lidas as doze e onze delas descartadas
  // em memória, logo a seguir a serem pagas. Agora o filtro é do lado do
  // servidor e a query devolve só o que há mesmo para fazer — quase
  // sempre nada.
  //
  // Depende de as ocorrências nascerem com `reminderSentAt: null`
  // explícito (ver `generateRecurringOccurrences.ts` e
  // `firebase_session_occurrence_repository.dart#createOccurrence`): o
  // Firestore não encontra `== null` onde o campo não existe. Uma
  // ocorrência criada antes desta mudança nunca entra nesta query — e é
  // isso que o script `backfill-reminder-field.mjs` vai lá corrigir.
  const occurrences = await tenantRef
    .collection('sessionOccurrences')
    .where('status', '==', 'scheduled')
    .where('reminderSentAt', '==', null)
    .where('startAt', '>=', now)
    .where('startAt', '<=', horizon)
    .get();

  let notified = 0;
  let processed = 0;

  for (const occurrence of occurrences.docs) {
    const bookings = await occurrence.ref
      .collection('bookings')
      .where('status', '==', 'booked')
      .get();

    // Marca-se SEMPRE, mesmo sem ninguém inscrito: sem isto, uma
    // sessão vazia era relida a cada hora até começar.
    await occurrence.ref.update({ reminderSentAt: FieldValue.serverTimestamp() });
    processed += 1;

    const memberIds = bookings.docs.map((doc) => doc.get('memberId') as string);
    if (memberIds.length === 0) continue;

    // Sem hora absoluta, de propósito: o runtime não sabe o fuso do
    // aluno (ver `describeOccurrence` em `notifications.ts`), e uma
    // hora errada metade do ano seria pior do que nenhuma. "Daqui a
    // cerca de N horas" é verdade em qualquer fuso.
    const startAt = (
      occurrence.get('startAt') as FirebaseFirestore.Timestamp
    ).toDate();
    const hoursUntil = Math.max(
      1,
      Math.round((startAt.getTime() - now.getTime()) / 3600_000),
    );

    const result = await notifyMembers(
      tenantRef,
      memberIds,
      'Tens treino marcado',
      `A tua sessão é daqui a cerca de ${hoursUntil} ${
        hoursUntil === 1 ? 'hora' : 'horas'
      }. Se já não puderes vir, cancela na app para libertares o lugar.`,
    );
    notified += result.targets;
    void result.sent;
  }

  return { occurrences: processed, notified };
}

/**
 * Nota sobre quem marca DEPOIS do aviso já ter saído: não recebe
 * lembrete, porque a marca é por sessão e não por marcação. É
 * deliberado — quem marcou já dentro da janela (menos de N horas
 * antes) marcou-a a pensar nela, e uma marca por marcação obrigava a
 * uma escrita extra por aluno em cada aula, todos os dias.
 */
