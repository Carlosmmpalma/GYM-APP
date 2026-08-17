import '../domain/entities/training_plan_entry.dart';

/// Fase 8 (UC13/UC15/UC16) — o plano de treino de UM membro (lista de
/// prescrições, cada uma referenciando um [Exercise] da biblioteca
/// partilhada). Escrita direta do cliente (Instrutor/Gestor).
abstract class TrainingPlanRepository {
  Stream<List<TrainingPlanEntry>> watchPlan(String memberId);

  /// UC13 — "Adicionar exercício ao plano": [initialLoad] fica também
  /// como o primeiro registo de `LoadHistoryRepository` (mesma
  /// invariante de [updateLoad] — nunca um valor sem histórico por
  /// trás), `null` quando o exercício não tem carga (isométrico, ex.:
  /// Prancha).
  Future<String> addEntry({
    required String memberId,
    required String exerciseId,
    required int sets,
    required int reps,
    double? initialLoad,
    required String recordedBy,
  });

  Future<void> updateSetsReps({
    required String memberId,
    required String entryId,
    required int sets,
    required int reps,
  });

  /// UC16 (fechado) — "cada atualização de carga cria um novo
  /// registo". Atualiza SEMPRE as duas coisas juntas, na mesma escrita
  /// atómica (`WriteBatch`, sem invariante cross-documento a validar,
  /// por isso não precisa de Cloud Function): `currentLoad` desta
  /// entrada (o que o plano mostra) E um `LoadHistoryEntry` novo (o
  /// histórico, nunca sobrescrito) — nunca uma sem a outra, para o
  /// histórico e o plano nunca divergirem.
  Future<void> updateLoad({
    required String memberId,
    required String entryId,
    required String exerciseId,
    required double load,
    required int reps,
    required String recordedBy,
  });

  Future<void> removeEntry({
    required String memberId,
    required String entryId,
  });
}
