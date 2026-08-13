import '../domain/entities/session_occurrence.dart';

abstract class SessionOccurrenceRepository {
  /// Fase 2: lista todas as ocorrências futuras de um serviço. Sem
  /// paginação/filtros por instrutor/modalidade ainda — isso é Fase 5+
  /// (Firestore Data Model v1 §47, secção Calendar).
  Stream<List<SessionOccurrence>> watchUpcomingOccurrences(String serviceId);

  Future<SessionOccurrence?> getOccurrence(String occurrenceId);
}
