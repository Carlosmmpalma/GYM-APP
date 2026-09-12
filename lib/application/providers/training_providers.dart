import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/assessment.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/load_history_entry.dart';
import '../../domain/entities/training_plan_entry.dart';
import '../../domain/entities/training_workout.dart';
import '../../infrastructure/firebase/firebase_assessment_repository.dart';
import '../../infrastructure/firebase/firebase_exercise_repository.dart';
import '../../infrastructure/firebase/firebase_load_history_repository.dart';
import '../../infrastructure/firebase/firebase_storage_repository.dart';
import '../../infrastructure/firebase/firebase_training_plan_repository.dart';
import '../../repositories/assessment_repository.dart';
import '../../repositories/exercise_repository.dart';
import '../../repositories/load_history_repository.dart';
import '../../repositories/storage_repository.dart';
import '../../repositories/training_plan_repository.dart';
import '../../domain/entities/workout_session.dart';
import '../../infrastructure/firebase/firebase_workout_session_repository.dart';
import '../../repositories/workout_session_repository.dart';
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';
import '../../domain/entities/exercise_category.dart';
import '../../infrastructure/firebase/firebase_exercise_category_repository.dart';
import '../../repositories/exercise_category_repository.dart';

/// Fase 8 — avaliações, histórico de carga, biblioteca de exercícios,
/// plano de treino.
final assessmentRepositoryProvider = Provider<AssessmentRepository>((ref) {
  return FirebaseAssessmentRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final assessmentsProvider = StreamProvider.autoDispose
    .family<List<Assessment>, String>((ref, memberId) {
  return ref.watch(assessmentRepositoryProvider).watchAssessments(memberId);
});

final loadHistoryRepositoryProvider = Provider<LoadHistoryRepository>((ref) {
  return FirebaseLoadHistoryRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final loadHistoryProvider = StreamProvider.autoDispose
    .family<List<LoadHistoryEntry>, ({String memberId, String exerciseId})>(
        (ref, args) {
  return ref.watch(loadHistoryRepositoryProvider).watchHistory(
        memberId: args.memberId,
        exerciseId: args.exerciseId,
      );
});

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return FirebaseExerciseRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final exerciseCategoryRepositoryProvider =
    Provider<ExerciseCategoryRepository>((ref) {
  return FirebaseExerciseCategoryRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// As categorias definidas pelo estúdio.
///
/// Pequena e estável (uma dúzia de documentos, mudam raramente), por
/// isso um listener aberto durante a sessão não é caro — ao contrário
/// da biblioteca de exercícios, que é grande e por isso passou a ser
/// pedida à peça (`exercisesByIdsProvider`).
final exerciseCategoriesProvider =
    StreamProvider<List<ExerciseCategory>>((ref) {
  return ref.watch(exerciseCategoryRepositoryProvider).watchCategories();
});

/// As categorias que os exercícios já usam mas que ainda não existem
/// como documento — o que ficou de quando a lista estava no código.
final exerciseCategoryNamesInUseProvider =
    FutureProvider.autoDispose<Set<String>>((ref) {
  return ref.watch(exerciseCategoryRepositoryProvider).namesInUse();
});

final exercisesProvider = StreamProvider<List<Exercise>>((ref) {
  return ref.watch(exerciseRepositoryProvider).watchExercises();
});

/// Chave estável para [exercisesByIdsProvider].
///
/// As famílias do Riverpod comparam a chave por `==`, e nem `Set` nem
/// `List` têm igualdade por valor em Dart: passar a coleção diretamente
/// criaria um provider novo (e uma leitura nova) a cada reconstrução do
/// ecrã. Ordenar e juntar numa string dá uma chave que compara bem e é
/// a mesma para o mesmo conjunto de exercícios, seja qual for a ordem
/// por que chegaram.
String exerciseKeyFor(Iterable<String> ids) {
  final unique = ids.where((id) => id.isNotEmpty).toSet().toList()..sort();
  return unique.join(',');
}

/// Só os exercícios de que o ecrã precisa, indexados por id.
///
/// A alternativa era [exercisesProvider], que traz a biblioteca INTEIRA
/// — e é o que os ecrãs do aluno faziam para resolver o nome de meia
/// dúzia de exercícios. Ver a nota em
/// `ExerciseRepository.getExercisesByIds`.
///
/// `autoDispose` porque o conjunto muda de ecrã para ecrã: manter vivos
/// os pedidos de todos os planos já abertos não pouparia leitura
/// nenhuma e só ocuparia memória.
final exercisesByIdsProvider =
    FutureProvider.autoDispose.family<Map<String, Exercise>, String>(
  (ref, key) async {
    final ids = key.isEmpty ? <String>{} : key.split(',').toSet();
    if (ids.isEmpty) return const {};
    final exercises =
        await ref.watch(exerciseRepositoryProvider).getExercisesByIds(ids);
    return {for (final exercise in exercises) exercise.id: exercise};
  },
);

final trainingPlanRepositoryProvider = Provider<TrainingPlanRepository>((ref) {
  return FirebaseTrainingPlanRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final workoutSessionRepositoryProvider =
    Provider<WorkoutSessionRepository>((ref) {
  return FirebaseWorkoutSessionRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// Fase 11 — histórico de treinos feitos, do mais recente para o mais
/// antigo.
final workoutSessionsProvider = StreamProvider.autoDispose
    .family<List<WorkoutSession>, String>((ref, memberId) {
  return ref.watch(workoutSessionRepositoryProvider).watchSessions(memberId);
});

/// A sessão em curso, se houver. É o que faz o botão dizer "Continuar
/// treino" em vez de "Iniciar treino".
final activeWorkoutSessionProvider =
    StreamProvider.autoDispose.family<WorkoutSession?, String>((ref, memberId) {
  return ref
      .watch(workoutSessionRepositoryProvider)
      .watchActiveSession(memberId);
});

/// Fase 11 — os treinos do plano de um membro ("Treino A — Costas").
final memberWorkoutsProvider = StreamProvider.autoDispose
    .family<List<TrainingWorkout>, String>((ref, memberId) {
  return ref.watch(trainingPlanRepositoryProvider).watchWorkouts(memberId);
});

final trainingPlanProvider = StreamProvider.autoDispose
    .family<List<TrainingPlanEntry>, String>((ref, memberId) {
  return ref.watch(trainingPlanRepositoryProvider).watchPlan(memberId);
});

// Aqui viveu o `avatarUrlProvider`, que pedia ao Storage o URL de cada
// avatar. Era um pedido de rede POR PESSOA — cinquenta numa lista de
// cinquenta, e outros cinquenta ao reentrar no ecrã. O URL passou a ser
// escrito no documento da pessoa pela `resizeAvatar`, por isso já vem
// com dados que a app lê de qualquer maneira e não há nada a pedir.
// `getDownloadUrl` continua a existir no repositório para o vídeo de
// exercícios, que é pedido um de cada vez, quando alguém o abre.

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return FirebaseStorageRepository(
    ref.watch(firebaseStorageProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});
