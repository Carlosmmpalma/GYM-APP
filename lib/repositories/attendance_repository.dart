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
}
