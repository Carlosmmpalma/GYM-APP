import { FieldValue } from 'firebase-admin/firestore';

/**
 * O mapa de aulas que se vê sem conta.
 *
 * ## Porque existe
 *
 * Até aqui, quem instalava a app antes de se inscrever encontrava um
 * formulário de login e mais nada — não conseguia saber sequer que aulas
 * o estúdio dá. Serve também a quem revê a app na App Store: sem isto,
 * abre-a, vê um campo de password, e não tem como perceber o que ali
 * está.
 *
 * ## Porque é derivado, e não escrito à mão
 *
 * A alternativa era o Gestor manter um cartaz num ecrã de definições. Um
 * horário escrito à mão desatualiza-se na primeira vez que alguém muda
 * uma aula e se esquece do cartaz — e um horário público errado é pior
 * do que não ter nenhum, porque manda pessoas ao ginásio à hora errada.
 *
 * Sai das `sessionSeries` ativas, que são a fonte de verdade, e é
 * reescrito pelo mesmo cron diário que gera as ocorrências. Sem
 * manutenção.
 *
 * ## O que NÃO vai lá dentro
 *
 * Isto é público, por isso o conteúdo é exatamente o que estaria num
 * cartaz na montra: modalidade ou serviço, dia, hora, duração. Nada de
 * nomes de alunos, lotações ocupadas, instrutores ou ids que sirvam para
 * pedir outra coisa qualquer. A capacidade vai — é a informação útil
 * "esta aula é de 8 pessoas" — mas nunca quantas estão ocupadas.
 */
export interface PublicScheduleEntry {
  /** O que se anuncia: a modalidade quando existe, senão o serviço. */
  name: string;
  /** segunda=1 … domingo=7, mesma convenção de `lib/isoWeek.ts`. */
  dayOfWeek: number;
  /** Hora do relógio do estúdio, "19:00". */
  startTime: string;
  durationMinutes: number;
  capacity: number;
}

/**
 * Recolhe e escreve a vitrina de um tenant.
 *
 * Devolve quantas entradas ficaram, para o resumo do cron.
 */
export async function publishPublicSchedule(
  tenantRef: FirebaseFirestore.DocumentReference,
  series: {
    serviceId: string;
    modalityId: string | null;
    dayOfWeek: number;
    startTime: string;
    durationMinutes: number;
    capacity: number;
  }[],
): Promise<number> {
  // Os nomes vêm de duas coleções pequenas, lidas uma vez por tenant e
  // por dia. Resolver o nome série a série seria uma leitura por aula.
  const [servicesSnap, modalitiesSnap] = await Promise.all([
    tenantRef.collection('services').get(),
    tenantRef.collection('modalities').get(),
  ]);

  const serviceNames = new Map(
    servicesSnap.docs.map((doc) => [doc.id, (doc.get('name') as string) ?? '']),
  );
  const modalityNames = new Map(
    modalitiesSnap.docs.map((doc) => [doc.id, (doc.get('name') as string) ?? '']),
  );

  const entries: PublicScheduleEntry[] = series
    .map((s) => {
      const name =
        (s.modalityId ? modalityNames.get(s.modalityId) : undefined) ||
        serviceNames.get(s.serviceId) ||
        '';
      return {
        name,
        dayOfWeek: s.dayOfWeek,
        startTime: s.startTime,
        durationMinutes: s.durationMinutes,
        capacity: s.capacity,
      };
    })
    // Uma série cujo serviço foi apagado ficaria como uma linha sem
    // nome. Melhor não anunciar do que anunciar um espaço em branco.
    .filter((entry) => entry.name.length > 0)
    .sort((a, b) =>
      a.dayOfWeek !== b.dayOfWeek
        ? a.dayOfWeek - b.dayOfWeek
        : a.startTime.localeCompare(b.startTime),
    );

  await tenantRef.collection('public').doc('schedule').set({
    entries,
    // Para a app poder dizer desde quando é este horário, em vez de
    // apresentar como atual um mapa que pode ter deixado de ser
    // reescrito sem ninguém dar por isso.
    updatedAt: FieldValue.serverTimestamp(),
  });

  return entries.length;
}
