import '../domain/entities/attendance.dart';

/// Fase 6 (UC10-A) — escrita direta do cliente (Manager OU Instrutor):
/// documento isolado, sem contador nem invariante cross-documento (ao
/// contrário de booking/usage), não precisa de Cloud Function.
abstract class AttendanceRepository {
  Stream<List<Attendance>> watchAttendanceForOccurrence(String occurrenceId);

  Future<void> recordAttendance({
    required String occurrenceId,
    required String memberId,
    required AttendanceStatus status,
    required String recordedBy,
  });

  /// Apaga o registo, devolvendo o inscrito a "por marcar".
  ///
  /// Não é o mesmo que marcar falta, e a diferença conta: uma falta é
  /// uma afirmação sobre o aluno e entra nas contas de retenção; "por
  /// marcar" é a ausência de afirmação. Sem isto, um toque errado num
  /// nome não tinha volta — só se podia trocar por outra afirmação
  /// igualmente errada.
  ///
  /// Apagar é permitido pelas mesmas Rules que a escrita
  /// (`allow write` cobre `delete`), por isso não há regra nova.
  Future<void> clearAttendance({
    required String occurrenceId,
    required String memberId,
  });
}
