import '../domain/entities/exercise.dart';

/// Fase 8 (UC15 fechado) — biblioteca de exercícios partilhada por
/// todos os instrutores do tenant. Escrita direta do cliente
/// (Instrutor/Gestor) — sem invariante cross-documento, mesmo padrão
/// de `ServiceRepository`/`ModalityRepository`.
abstract class ExerciseRepository {
  Stream<List<Exercise>> watchExercises();

  /// Só os exercícios indicados.
  ///
  /// Existe porque os ecrãs do ALUNO (o plano dele, o treino em curso,
  /// o histórico) precisam de resolver o nome de meia dúzia de
  /// exercícios, e estavam a carregar a biblioteca inteira para isso.
  /// Hoje são 61 documentos; num estúdio a sério são 200 ou 300, e o
  /// custo cresce com a biblioteca em vez de crescer com o que o aluno
  /// treina — que é a métrica errada.
  ///
  /// O `whereIn` do Firestore aceita 30 valores, por isso a
  /// implementação parte em blocos. Um plano com mais de 30 exercícios
  /// distintos é raro; quando acontece, são duas leituras em vez de
  /// uma, e continua a ser menos do que a biblioteca toda.
  Future<List<Exercise>> getExercisesByIds(Set<String> ids);

  Future<String> createExercise({
    required String name,
    required String description,
    required String category,
  });

  Future<void> updateExercise({
    required String exerciseId,
    required String name,
    required String description,
    required String category,
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
