import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/exercise.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/training_plan_entry.dart';
import 'package:gym_saas/domain/entities/training_workout.dart';
import 'package:gym_saas/presentation/screens/training_plan_editor_screen.dart';
import 'package:gym_saas/repositories/training_plan_repository.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';
const _staffId = 'staff_1';

/// UC16 fechado — prova que "Atualizar carga" chama sempre
/// `updateLoad` (nunca um `update` de campo isolado que perderia o
/// histórico) — mesmo padrão de fake usado nos outros testes de
/// booking desta app.
class _FakeTrainingPlanRepository implements TrainingPlanRepository {
  _FakeTrainingPlanRepository(this.entries);

  final List<TrainingPlanEntry> entries;
  ({
    String entryId,
    double load,
    int reps,
    String recordedBy
  })? lastUpdateLoadCall;

  @override
  Stream<List<TrainingPlanEntry>> watchPlan(String memberId) =>
      Stream.value(entries);

  @override
  Future<String> addEntry({
    required String memberId,
    required String exerciseId,
    required int sets,
    required String reps,
    double? initialLoad,
    required String recordedBy,
    String? workoutId,
    int position = 0,
    int? restSeconds,
    String notes = '',
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateSetsReps({
    required String memberId,
    required String entryId,
    required int sets,
    required String reps,
    int? restSeconds,
    String? notes,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateLoad({
    required String memberId,
    required String entryId,
    required String exerciseId,
    required double load,
    required int reps,
    required String recordedBy,
  }) async {
    lastUpdateLoadCall =
        (entryId: entryId, load: load, reps: reps, recordedBy: recordedBy);
  }

  @override
  Future<void> removeEntry(
          {required String memberId, required String entryId}) =>
      throw UnimplementedError();
  @override
  Stream<List<TrainingWorkout>> watchWorkouts(String memberId) =>
      Stream.value(workouts);

  List<TrainingWorkout> workouts = const [];

  @override
  Future<String> addWorkout({
    required String memberId,
    required String name,
    String notes = '',
    required int position,
  }) async =>
      'workout_1';

  @override
  Future<void> updateWorkout({
    required String memberId,
    required String workoutId,
    String? name,
    String? notes,
    int? position,
    bool? active,
  }) async {}

  @override
  Future<void> removeWorkout({
    required String memberId,
    required String workoutId,
  }) async {}

  @override
  Future<void> moveEntry({
    required String memberId,
    required String entryId,
    required String? workoutId,
    required int position,
  }) async {}

  @override
  Future<void> reorderEntries({
    required String memberId,
    required List<String> orderedEntryIds,
  }) async {
    reorderedTo = orderedEntryIds;
  }

  List<String>? reorderedTo;
}

void main() {
  const member = MemberSummary(
    uid: _memberId,
    memberNumber: '000001',
    name: 'Rita Ferreira',
    active: true,
  );
  const exercise = Exercise(
    id: 'exercise_1',
    name: 'Agachamento com barra',
    description: '',
    category: 'Pernas',
  );
  const entry = TrainingPlanEntry(
    id: 'entry_1',
    memberId: _memberId,
    exerciseId: 'exercise_1',
    sets: 4,
    reps: '8',
    currentLoad: 60,
  );

  Widget buildApp(_FakeTrainingPlanRepository repository) {
    return ProviderScope(
      overrides: [
        trainingPlanRepositoryProvider.overrideWithValue(repository),
        exercisesProvider.overrideWith((ref) => Stream.value(const [exercise])),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
                uid: _staffId, tenantId: _tenantId, roles: {Role.instructor}),
          ),
        ),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(currentAppUserProvider);
            return const TrainingPlanEditorScreen(member: member);
          },
        ),
      ),
    );
  }

  testWidgets('mostra a entrada do plano com séries/reps/carga',
      (tester) async {
    final repository = _FakeTrainingPlanRepository([entry]);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Agachamento com barra'), findsOneWidget);
    // Fase 11 — a linha ficou mais compacta para dar espaço ao descanso
    // e à nota, que agora também cabem aqui.
    expect(find.text('4 × 8 · 60.0 kg'), findsOneWidget);
  });

  testWidgets(
      'atualizar carga chama updateLoad (nunca sobrescreve — UC16 fechado)',
      (tester) async {
    final repository = _FakeTrainingPlanRepository([entry]);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atualizar carga'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Carga (kg)'), '62.5');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repository.lastUpdateLoadCall?.entryId, 'entry_1');
    expect(repository.lastUpdateLoadCall?.load, 62.5);
    expect(repository.lastUpdateLoadCall?.recordedBy, _staffId);
  });

  group('treinos (Fase 11)', () {
    testWidgets('plano vazio explica a estrutura, não pede um exercício',
        (tester) async {
      // Antes dizia "adiciona o primeiro exercício". Um plano começa por
      // um treino — é assim que um instrutor prescreve.
      final repository = _FakeTrainingPlanRepository(const []);
      await tester.pumpWidget(buildApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('Sem plano de treino'), findsOneWidget);
      expect(find.text('Criar o primeiro treino'), findsOneWidget);
    });

    testWidgets('agrupa os exercícios pelo treino a que pertencem',
        (tester) async {
      const costas = TrainingPlanEntry(
        id: 'e1',
        memberId: _memberId,
        exerciseId: 'exercise_1',
        sets: 4,
        reps: '8',
        workoutId: 'w1',
      );
      const pernas = TrainingPlanEntry(
        id: 'e2',
        memberId: _memberId,
        exerciseId: 'exercise_2',
        sets: 3,
        reps: '12',
        workoutId: 'w2',
      );

      final repository = _FakeTrainingPlanRepository([costas, pernas])
        ..workouts = const [
          TrainingWorkout(
            id: 'w1',
            memberId: _memberId,
            name: 'Treino A — Costas',
            position: 0,
          ),
          TrainingWorkout(
            id: 'w2',
            memberId: _memberId,
            name: 'Treino B — Pernas',
            position: 1,
          ),
        ];

      await tester.pumpWidget(buildApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('TREINO A — COSTAS'), findsOneWidget);
      expect(find.text('TREINO B — PERNAS'), findsOneWidget);
      // Cada treino conta só os seus.
      expect(find.text('1 exercício(s)'), findsNWidgets(2));
    });

    testWidgets('exercícios sem treino aparecem num grupo próprio',
        (tester) async {
      // O caso das entradas criadas antes de existirem treinos, e o das
      // que ficam soltas ao apagar um. Não podem desaparecer.
      const solto = TrainingPlanEntry(
        id: 'e1',
        memberId: _memberId,
        exerciseId: 'exercise_1',
        sets: 4,
        reps: '8',
      );
      final repository = _FakeTrainingPlanRepository([solto]);

      await tester.pumpWidget(buildApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('SEM TREINO ATRIBUÍDO'), findsOneWidget);
    });

    testWidgets('a prescrição aceita texto, não só números', (tester) async {
      // "45s" era impossível de representar: `reps` era um inteiro, e o
      // próprio comentário do domínio dava a prancha como exemplo do
      // que não cabia lá.
      const prancha = TrainingPlanEntry(
        id: 'e1',
        memberId: _memberId,
        exerciseId: 'exercise_1',
        sets: 3,
        reps: '45s',
        workoutId: 'w1',
      );
      final repository = _FakeTrainingPlanRepository([prancha])
        ..workouts = const [
          TrainingWorkout(id: 'w1', memberId: _memberId, name: 'Treino A'),
        ];

      await tester.pumpWidget(buildApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('3 × 45s'), findsOneWidget);
    });
  });
}
