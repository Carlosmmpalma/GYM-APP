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
    required int reps,
    double? initialLoad,
    required String recordedBy,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateSetsReps({
    required String memberId,
    required String entryId,
    required int sets,
    required int reps,
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
    muscleGroup: 'Pernas',
  );
  const entry = TrainingPlanEntry(
    id: 'entry_1',
    memberId: _memberId,
    exerciseId: 'exercise_1',
    sets: 4,
    reps: 8,
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
    expect(find.text('4 séries × 8 reps — 60.0 kg'), findsOneWidget);
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
}
