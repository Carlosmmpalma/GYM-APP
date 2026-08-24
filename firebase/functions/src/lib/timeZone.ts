/**
 * Última ronda — as horas das aulas andavam uma hora no verão.
 *
 * Uma série guarda `startTime: "19:00"` — a hora a que a aula começa,
 * escrita por quem a criou a olhar para o relógio da parede. A geração
 * das ocorrências fazia `startAt.setUTCHours(19, 0)`, ou seja tratava
 * essas 19:00 como **UTC**. Em Portugal isso está certo no inverno e
 * errado no verão: de finais de março a finais de outubro Lisboa é
 * UTC+1, e a mesma aula passava a aparecer às 20:00 na app — para o
 * aluno, para o instrutor, para toda a gente, durante sete meses por
 * ano. As sessões avulsas não tinham o problema (nascem de um seletor
 * de data/hora, já com o instante certo), o que tornava tudo ainda
 * mais confuso: as aulas da série apareciam uma hora depois das outras.
 *
 * **Sem dependência nova.** O Node traz os dados de fusos horários
 * completos (ICU) e o `Intl` sabe responder a "que horas eram em
 * Lisboa neste instante?". Com isso mede-se o desvio e faz-se a
 * conversão à mão — que é o que uma biblioteca de datas faria por
 * baixo, e são trinta linhas.
 */

/** Fuso do estúdio quando o documento do tenant não diz outra coisa. */
export const DEFAULT_TIME_ZONE = 'Europe/Lisbon';

/**
 * Quantos minutos [timeZone] está à frente do UTC **neste instante**.
 * Positivo a leste de Greenwich (Lisboa no verão: +60).
 */
function offsetMinutesAt(instant: Date, timeZone: string): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const parts = formatter.formatToParts(instant);
  const value = (type: string) =>
    Number(parts.find((part) => part.type === type)?.value ?? '0');

  // O relógio local, lido como se fosse UTC: a diferença para o
  // instante verdadeiro é exatamente o desvio do fuso.
  const asIfUtc = Date.UTC(
    value('year'),
    value('month') - 1,
    value('day'),
    value('hour'),
    value('minute'),
    value('second'),
  );
  return Math.round((asIfUtc - instant.getTime()) / 60_000);
}

/**
 * O instante em que o relógio de [timeZone] marca a data e hora dadas.
 *
 * Duas passagens de propósito: a primeira estimativa usa o desvio
 * medido no sítio errado da linha do tempo, o que só falha nos dias em
 * que o relógio muda — e é precisamente aí que interessa acertar.
 *
 * Nas horas que não existem (a madrugada em que o relógio salta para a
 * frente) devolve o instante logo a seguir ao salto, e nas horas
 * repetidas (quando recua) devolve a primeira das duas. Nenhum ginásio
 * marca aulas às 01:30 de domingo, mas é melhor ter uma resposta
 * definida do que uma ao acaso.
 */
export function zonedWallClockToUtc(params: {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  timeZone: string;
}): Date {
  const { year, month, day, hour, minute, timeZone } = params;
  const wallClockAsUtc = Date.UTC(year, month - 1, day, hour, minute);

  const firstGuess = new Date(
    wallClockAsUtc - offsetMinutesAt(new Date(wallClockAsUtc), timeZone) * 60_000,
  );
  const refinedOffset = offsetMinutesAt(firstGuess, timeZone);
  return new Date(wallClockAsUtc - refinedOffset * 60_000);
}

/** A data e hora que o relógio de [timeZone] mostra em [instant]. */
export function utcToZonedWallClock(
  instant: Date,
  timeZone: string,
): { year: number; month: number; day: number; hour: number; minute: number } {
  const shifted = new Date(
    instant.getTime() + offsetMinutesAt(instant, timeZone) * 60_000,
  );
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
  };
}

/**
 * Adianta [weeks] semanas mantendo a HORA DO RELÓGIO.
 *
 * Somar `7 * 24 * 60 * 60 * 1000` parece o mesmo e não é: na semana em
 * que o relógio muda, a aula das 19:00 passaria a ser às 18:00 ou às
 * 20:00. O que se repete todas as semanas é a hora a que as pessoas
 * aparecem no ginásio, não o número de milissegundos.
 */
export function addWeeksPreservingWallClock(
  instant: Date,
  weeks: number,
  timeZone: string,
): Date {
  const local = utcToZonedWallClock(instant, timeZone);
  // A soma dos dias é feita no calendário, não em milissegundos.
  const shiftedDate = new Date(
    Date.UTC(local.year, local.month - 1, local.day + weeks * 7),
  );
  return zonedWallClockToUtc({
    year: shiftedDate.getUTCFullYear(),
    month: shiftedDate.getUTCMonth() + 1,
    day: shiftedDate.getUTCDate(),
    hour: local.hour,
    minute: local.minute,
    timeZone,
  });
}

/** O fuso configurado no tenant, ou o de Lisboa. */
export async function tenantTimeZone(
  tenantRef: FirebaseFirestore.DocumentReference,
): Promise<string> {
  try {
    const snapshot = await tenantRef.get();
    const timeZone = snapshot.get('timezone') as string | undefined;
    return timeZone && timeZone.length > 0 ? timeZone : DEFAULT_TIME_ZONE;
  } catch (error) {
    return DEFAULT_TIME_ZONE;
  }
}
