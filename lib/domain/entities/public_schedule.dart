import 'package:equatable/equatable.dart';

/// Uma aula tal como aparece no mapa público.
///
/// É de propósito muito mais pobre do que [SessionSeries]: isto lê-se
/// sem sessão nenhuma, por isso só leva o que já estaria num cartaz na
/// montra. Sem instrutor, sem ids, sem lotação ocupada — ver a regra
/// `tenants/{t}/public/{doc}` em `firestore.rules` e
/// `lib/publicSchedule.ts` do lado do servidor.
class PublicScheduleEntry extends Equatable {
  const PublicScheduleEntry({
    required this.name,
    required this.dayOfWeek,
    required this.startTime,
    required this.durationMinutes,
    required this.capacity,
  });

  /// A modalidade quando existe, senão o serviço.
  final String name;

  /// segunda=1 … domingo=7.
  final int dayOfWeek;

  /// Hora do relógio do estúdio, "19:00".
  final String startTime;

  final int durationMinutes;
  final int capacity;

  @override
  List<Object?> get props =>
      [name, dayOfWeek, startTime, durationMinutes, capacity];
}

/// O mapa completo, mais quando foi escrito.
class PublicSchedule extends Equatable {
  const PublicSchedule({required this.entries, this.updatedAt});

  final List<PublicScheduleEntry> entries;

  /// Quando a função agendada o reescreveu pela última vez.
  ///
  /// Serve para o ecrã poder calar-se quando o mapa está velho: um
  /// horário público errado manda pessoas ao ginásio à hora errada, e
  /// isso é pior do que não mostrar horário nenhum.
  final DateTime? updatedAt;

  bool get isEmpty => entries.isEmpty;

  /// Um mapa que não é reescrito há mais de uma semana deixou de ser de
  /// confiança — o cron corre todos os dias, por isso sete dias de
  /// silêncio significam que alguma coisa parou.
  bool isStale(DateTime now) {
    final at = updatedAt;
    if (at == null) return true;
    return now.difference(at).inDays > 7;
  }

  @override
  List<Object?> get props => [entries, updatedAt];
}
