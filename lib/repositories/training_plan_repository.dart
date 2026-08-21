import '../domain/entities/training_plan_entry.dart';
import '../domain/entities/training_workout.dart';

/// UC13/UC15/UC16 — o plano de treino de um membro.
///
/// Fase 11 — ganhou uma camada. O plano deixou de ser uma lista corrida
/// de exercícios e passou a ter **treinos** ("Treino A — Costas",
/// "Treino B — Pernas"), cada um com os seus exercícios ordenados. É
/// como qualquer instrutor prescreve, e como as apps da área o fazem;
/// sem isso, um aluno que treina três vezes por semana via os exercícios
/// dos três dias misturados numa lista só.
abstract class TrainingPlanRepository {
  /// Todas as entradas do plano, ordenadas por [TrainingPlanEntry.position].
  /// A separação por treino faz-se em memória a partir do `workoutId` —
  /// são poucas dezenas de documentos e evita uma query por treino.
  Stream<List<TrainingPlanEntry>> watchPlan(String memberId);

  Stream<List<TrainingWorkout>> watchWorkouts(String memberId);

  Future<String> addWorkout({
    required String memberId,
    required String name,
    String notes,
    required int position,
  });

  Future<void> updateWorkout({
    required String memberId,
    required String workoutId,
    String? name,
    String? notes,
    int? position,
    bool? active,
  });

  /// Apaga o treino e deixa os exercícios dele **sem treino atribuído**,
  /// em vez de os apagar em cascata: a prescrição continua a ter valor,
  /// e o histórico de cargas ficaria sem contexto.
  Future<void> removeWorkout({
    required String memberId,
    required String workoutId,
  });

  Future<String> addEntry({
    required String memberId,
    required String exerciseId,
    required int sets,
    required String reps,
    double? initialLoad,
    required String recordedBy,
    String? workoutId,
    int position,
    int? restSeconds,
    String notes,
  });

  Future<void> updateSetsReps({
    required String memberId,
    required String entryId,
    required int sets,
    required String reps,
    int? restSeconds,
    String? notes,
  });

  /// Mudar um exercício de treino, ou tirá-lo de um (`workoutId: null`).
  Future<void> moveEntry({
    required String memberId,
    required String entryId,
    required String? workoutId,
    required int position,
  });

  /// Reordenar os exercícios dentro de um treino. A sequência não é
  /// decorativa: agachamento antes de extensão de pernas é uma decisão
  /// de treino.
  Future<void> reorderEntries({
    required String memberId,
    required List<String> orderedEntryIds,
  });

  /// UC16 — regista uma carga nova. Escreve o `currentLoad` da entrada e
  /// acrescenta um registo ao histórico, sempre juntos.
  ///
  /// [reps] é o que o aluno FEZ hoje, não a prescrição — e por isso não
  /// toca no `reps` da entrada.
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
