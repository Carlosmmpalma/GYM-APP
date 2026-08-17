import '../domain/entities/load_history_entry.dart';

/// Fase 8 (UC16 fechado) — histórico de carga por exercício, nunca
/// sobrescrito. Escrita direta do cliente (Instrutor/Gestor) — mesmo
/// raciocínio de `AttendanceRepository`, documento novo isolado sem
/// invariante cross-documento (não mexe em `TrainingPlanEntry`, quem
/// garante que os dois ficam coerentes é o caller — ver
/// `TrainingPlanRepository.updateLoad`).
abstract class LoadHistoryRepository {
  /// UC16 (atualizado) — mais recente primeiro, para o gráfico de
  /// evolução do Aluno.
  Stream<List<LoadHistoryEntry>> watchHistory({
    required String memberId,
    required String exerciseId,
  });

  Future<void> addEntry({
    required String memberId,
    required String exerciseId,
    required double load,
    required int reps,
    required String recordedBy,
  });
}
