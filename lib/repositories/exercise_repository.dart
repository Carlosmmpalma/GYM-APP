import '../domain/entities/exercise.dart';

/// Fase 8 (UC15 fechado) — biblioteca de exercícios partilhada por
/// todos os instrutores do tenant. Escrita direta do cliente
/// (Instrutor/Gestor) — sem invariante cross-documento, mesmo padrão
/// de `ServiceRepository`/`ModalityRepository`.
abstract class ExerciseRepository {
  Stream<List<Exercise>> watchExercises();

  Future<String> createExercise({
    required String name,
    required String description,
    required String muscleGroup,
  });

  Future<void> updateExercise({
    required String exerciseId,
    required String name,
    required String description,
    required String muscleGroup,
  });

  /// Chamado depois do upload para o Storage terminar
  /// (`StorageRepository.uploadExerciseVideo`) — só grava o caminho,
  /// nunca faz upload nenhum ele próprio (essa responsabilidade fica
  /// isolada no `StorageRepository`, Platform Foundation §19: "a
  /// camada de Storage deve ser abstraída").
  Future<void> setVideoPath({
    required String exerciseId,
    required String? videoPath,
  });
}
