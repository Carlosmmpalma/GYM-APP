/**
 * Fase 4 (guia-desenvolvimento.md) — "Implementar cálculo de período
 * semanal (segunda 00:00 a domingo 23:59), não 'últimos 7 dias'".
 *
 * Espelha `lib/core/utils/iso_week.dart` (mesmo algoritmo, mesma
 * limitação documentada: cálculo em UTC, não no timezone do tenant —
 * ver a nota completa nesse ficheiro). As duas implementações têm de
 * concordar sempre na mesma chave para o mesmo instante, porque o
 * cliente (Dart) só usa isto para MOSTRAR a barra de utilização
 * (Fase 4 story 7); quem decide de facto se o limite foi atingido é
 * sempre esta versão, correndo em `createBooking`/`cancelBooking`
 * (Admin SDK, autoridade no backend — Firestore Data Model v1 §52).
 */

/** `YYYY-Www` (ex.: `2026-W33`). Semana começa à segunda-feira. */
export function isoWeekKey(date: Date): string {
  const dayOnly = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  const weekday = dayOnly.getUTCDay() === 0 ? 7 : dayOnly.getUTCDay(); // segunda=1 ... domingo=7
  const thursday = new Date(dayOnly);
  thursday.setUTCDate(dayOnly.getUTCDate() + (4 - weekday));
  const isoYear = thursday.getUTCFullYear();
  const jan1 = Date.UTC(isoYear, 0, 1);
  const weekNumber =
    Math.floor((thursday.getTime() - jan1) / (7 * 24 * 60 * 60 * 1000)) + 1;
  return `${isoYear}-W${String(weekNumber).padStart(2, '0')}`;
}

/** Início (segunda 00:00:00.000 UTC) e fim (domingo 23:59:59.999 UTC). */
export function isoWeekRange(date: Date): { start: Date; end: Date } {
  const dayOnly = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  const weekday = dayOnly.getUTCDay() === 0 ? 7 : dayOnly.getUTCDay();
  const monday = new Date(dayOnly);
  monday.setUTCDate(dayOnly.getUTCDate() - (weekday - 1));
  const sundayEnd = new Date(monday);
  sundayEnd.setUTCDate(monday.getUTCDate() + 7);
  sundayEnd.setUTCMilliseconds(sundayEnd.getUTCMilliseconds() - 1);
  return { start: monday, end: sundayEnd };
}

/**
 * Inverso de [isoWeekKey]: devolve a segunda-feira (00:00 UTC) da
 * semana identificada por [key] (`YYYY-Www`). Usado por
 * `recalculateUsage.ts` para recompor `periodStart`/`periodEnd` a
 * partir do `period` guardado num `Booking`, sem precisar de ir buscar
 * o `SessionOccurrence` outra vez. Algoritmo standard: 4 de janeiro
 * está sempre na semana 1 do ano ISO.
 */
export function isoWeekKeyToMonday(key: string): Date {
  const [yearPart, weekPart] = key.split('-W');
  const year = Number(yearPart);
  const week = Number(weekPart);
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jan4Weekday = jan4.getUTCDay() === 0 ? 7 : jan4.getUTCDay();
  const week1Monday = new Date(jan4);
  week1Monday.setUTCDate(jan4.getUTCDate() - (jan4Weekday - 1));
  const monday = new Date(week1Monday);
  monday.setUTCDate(week1Monday.getUTCDate() + (week - 1) * 7);
  return monday;
}
