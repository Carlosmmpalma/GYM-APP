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
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';

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

final exercisesProvider = StreamProvider<List<Exercise>>((ref) {
  return ref.watch(exerciseRepositoryProvider).watchExercises();
});

final trainingPlanRepositoryProvider = Provider<TrainingPlanRepository>((ref) {
  return FirebaseTrainingPlanRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
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

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return FirebaseStorageRepository(
    ref.watch(firebaseStorageProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});
