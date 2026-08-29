import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/exercise.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/training_plan_entry.dart';
import 'package:gym_saas/domain/entities/training_workout.dart';
import 'package:gym_saas/domain/entities/workout_session.dart';
import 'package:gym_saas/presentation/screens/my_training_plan_screen.dart';
import 'package:gym_saas/repositories/training_plan_repository.dart';
import 'package:gym_saas/repositories/workout_session_repository.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

/// Reportado pelo Carlos a testar: "o aluno não consegue ver qual é o
/// treino, apenas consegue ver os exercícios". Os treinos existiam no
/// editor do instrutor desde a Fase 11, mas o ecrã do aluno continuava
/// a mostrar uma lista corrida — 18 exercícios seguidos sem dizer quais
/// eram os de hoje.
class _FakePlanRepository implements TrainingPlanRepository {
  _FakePlanRepository({required this.entries, required this.workouts});

  final List<TrainingPlanEntry> entries;
  final List<TrainingWorkout> workouts;

  @override
  Stream<List<TrainingPlanEntry>> watchPlan(String memberId) =>
      Stream.value(entries);

  @override
  Stream<List<TrainingWorkout>> watchWorkouts(String memberId) =>
      Stream.value(workouts);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Sem sessão em curso — o `StartWorkoutButton` de cada treino observa
/// isto para decidir entre "Iniciar" e "Continuar".
class _FakeWorkoutSessionRepository implements WorkoutSessionRepository {
  @override
  Stream<WorkoutSession?> watchActiveSession(String memberId) =>
      Stream.value(null);

  @override
  Stream<List<WorkoutSession>> watchSessions(String memberId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  const exercises = [
    Exercise(
      id: 'ex_remada',
      name: 'Remada curvada',
      description: '',
      muscleGroup: 'Costas',
    ),
    Exercise(
      id: 'ex_supino',
      name: 'Supino plano',
      description: '',
      muscleGroup: 'Peito',
    ),
    Exercise(
      id: 'ex_abdominal',
      name: 'Abdominal',
      description: '',
      muscleGroup: 'Core',
    ),
  ];

  const workouts = [
    TrainingWorkout(
      id: 'w_costas',
      memberId: _memberId,
      name: 'Treino A — Costas',
      notes: 'Aquece 5 min na passadeira.',
    ),
    TrainingWorkout(
      id: 'w_peito',
      memberId: _memberId,
      name: 'Treino B — Peito',
      position: 1,
    ),
  ];

  const entries = [
    TrainingPlanEntry(
      id: 'e1',
      memberId: _memberId,
      exerciseId: 'ex_remada',
      sets: 4,
      reps: '8-12',
      workoutId: 'w_costas',
    ),
    TrainingPlanEntry(
      id: 'e2',
      memberId: _memberId,
      exerciseId: 'ex_supino',
      sets: 3,
      reps: '10',
      workoutId: 'w_peito',
    ),
    // Sem treino atribuído: tem de continuar visível, não desaparecer.
    TrainingPlanEntry(
      id: 'e3',
      memberId: _memberId,
      exerciseId: 'ex_abdominal',
      sets: 3,
      reps: '15',
    ),
  ];

  Widget buildApp({
    List<TrainingWorkout> workoutList = workouts,
    List<TrainingPlanEntry> entryList = entries,
  }) {
    return ProviderScope(
      overrides: [
        trainingPlanRepositoryProvider.overrideWithValue(
          _FakePlanRepository(entries: entryList, workouts: workoutList),
        ),
        workoutSessionRepositoryProvider
            .overrideWithValue(_FakeWorkoutSessionRepository()),
        // O ecrã deixou de carregar a biblioteca inteira: pede só os
        // exercícios que o plano/histórico deste aluno referencia.
        exercisesByIdsProvider.overrideWith(
          (ref, key) async => {for (final e in exercises) e.id: e},
        ),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
                uid: _memberId, tenantId: _tenantId, roles: {Role.member}),
          ),
        ),
      ],
      child: const MaterialApp(
        home: MyTrainingPlanScreen(memberId: _memberId),
      ),
    );
  }

  testWidgets('o aluno vê a que TREINO pertence cada exercício',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // O nome do treino aparece em maiúsculas (display).
    expect(find.text('TREINO A — COSTAS'), findsOneWidget);
    expect(find.text('TREINO B — PEITO'), findsOneWidget);
    expect(find.text('Remada curvada'), findsOneWidget);
    expect(find.text('Supino plano'), findsOneWidget);
  });

  testWidgets('as instruções do treino aparecem ao aluno', (tester) async {
    // O instrutor escreve-as no editor; até aqui só ele próprio as via.
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Aquece 5 min na passadeira.'), findsOneWidget);
  });

  testWidgets('cada treino tem o seu botão para começar', (tester) async {
    // Sem isto, começar o Treino B obrigava a voltar atrás e a escolher
    // outra vez numa folha que já tinha sido respondida ao ler o ecrã.
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Iniciar este treino'), findsNWidgets(2));
  });

  testWidgets('exercícios sem treino continuam visíveis, num grupo próprio',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('OUTROS EXERCÍCIOS'), findsOneWidget);
    expect(find.text('Abdominal'), findsOneWidget);
  });

  testWidgets('sem treinos definidos, o plano continua a mostrar-se',
      (tester) async {
    // Planos anteriores aos treinos existirem não podem ficar em branco.
    await tester.pumpWidget(buildApp(workoutList: const []));
    await tester.pumpAndSettle();

    expect(find.text('O TEU PLANO'), findsOneWidget);
    expect(find.text('Abdominal'), findsOneWidget);
  });
}
