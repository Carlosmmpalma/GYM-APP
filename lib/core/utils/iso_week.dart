/// Fase 4 (guia-desenvolvimento.md) — "Implementar cálculo de período
/// semanal (segunda 00:00 a domingo 23:59), não 'últimos 7 dias'".
///
/// Chave de período no formato ISO-8601 week date (`YYYY-Www`, ex.:
/// `2026-W33`) — mesmo formato usado no exemplo do `usage/{usageId}` em
/// `Firestore Data Model v1` §31. Cálculo em UTC, sem depender do
/// timezone do [Tenant] (`Tenant.timezone`, ex. `Europe/Lisbon`): uma
/// limitação conhecida e documentada, não escondida — perto da
/// fronteira segunda/domingo à meia-noite, o período contado pode
/// diferir por 1h (verão) do que seria com o timezone real do tenant.
/// Corrigir isto exigiria uma biblioteca de timezone (ex. `timezone`
/// package) que não está nas dependências do projeto; fica sinalizado
/// para quando isso for pedido explicitamente.
library;

/// Devolve a chave da semana ISO-8601 a que [date] pertence, no formato
/// `YYYY-Www` (ex.: `2026-W33`). Semana começa à segunda-feira.
String isoWeekKey(DateTime date) {
  final utc = date.toUtc();
  // Algoritmo ISO-8601 standard: a semana 1 de um ano é a que contém a
  // primeira quinta-feira desse ano. Ajusta para a quinta-feira da
  // mesma semana ISO (segunda=1 ... domingo=7) e conta semanas desde
  // 1 de janeiro desse ano ajustado.
  final ordinalDay = DateTime.utc(utc.year, utc.month, utc.day);
  final weekday = ordinalDay.weekday; // segunda=1 ... domingo=7
  final thursday = ordinalDay.add(Duration(days: 4 - weekday));
  final isoYear = thursday.year;
  final jan1 = DateTime.utc(isoYear, 1, 1);
  final weekNumber = ((thursday.difference(jan1).inDays) / 7).floor() + 1;
  return '$isoYear-W${weekNumber.toString().padLeft(2, '0')}';
}

/// Devolve o início (segunda-feira 00:00:00.000 UTC) e o fim
/// (domingo 23:59:59.999 UTC) da semana ISO a que [date] pertence.
({DateTime start, DateTime end}) isoWeekRange(DateTime date) {
  final utc = date.toUtc();
  final dayOnly = DateTime.utc(utc.year, utc.month, utc.day);
  final weekday = dayOnly.weekday; // segunda=1 ... domingo=7
  final monday = dayOnly.subtract(Duration(days: weekday - 1));
  final sundayEnd = monday
      .add(const Duration(days: 7))
      .subtract(const Duration(milliseconds: 1));
  return (start: monday, end: sundayEnd);
}
