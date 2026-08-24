import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/booking_providers.dart';
import 'package:gym_saas/application/providers/plan_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/domain/entities/exercise.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/training_plan_entry.dart';
import 'package:gym_saas/domain/entities/workout_session.dart';
import 'package:gym_saas/presentation/screens/group_workout_screen.dart';
import 'package:gym_saas/repositories/workout_session_repository.dart';

const _tenantId = 'tenant_test';
const _occurrenceId = 'occ_1';
const _instructorId = 'staff_1';

const _members = [
  MemberSummary(
    uid: 'member_rita',
    memberNumber: '000001',
    name: 'Rita Ferreira',
    active: true,
  ),
  MemberSummary(
    uid: 'member_joao',
    memberNumber: '000002',
    name: 'João Martins',
    active: true,
  ),
];

const _exercise = Exercise(
  id: 'ex_supino',
  name: 'Supino plano',
  description: '',
  muscleGroup: 'Peito',
);

Booking _booking(String memberId) => Booking(
      id: memberId,
      occurrenceId: _occurrenceId,
      memberId: memberId,
      status: BookingStatus.booked,
      source: BookingSource.self,
      isExtra: false,
      createdAt: DateTime(2026, 8, 20),
    );

/// Numa aula de dez, registar o treino de cada um abrindo a ficha, um a
/// um, é impossível de fazer com o telemóvel na mão — e o resultado
/// prático era não se registar nada. Este ecrã parte da AULA: turma
/// numa linha, começar para todos, saltar entre pessoas, fechar tudo.
class _FakeWorkoutSessionRepository implements WorkoutSessionRepository {
  final Map<String, WorkoutSession> active = {};
  final List<String> started = [];
  final List<String> finished = [];
  final List<String> discarded = [];

  @override
  Stream<WorkoutSession?> watchActiveSession(String memberId) =>
      Stream.value(active[memberId]);

  @override
  Future<String> startSession({
    required String memberId,
    required String? workoutId,
    required String workoutName,
    required String performedBy,
  }) async {
    started.add(memberId);
    active[memberId] = WorkoutSession(
      id: 'session_$memberId',
      memberId: memberId,
      workoutId: workoutId,
      workoutName: workoutName,
      startedAt: DateTime(2026, 8, 20, 19),
      performedBy: performedBy,
    );
    return 'session_$memberId';
  }

  @override
  Future<void> finishSession({
    required String memberId,
    required String sessionId,
    String notes = '',
  }) async {
    finished.add(memberId);
    active.remove(memberId);
  }

  @override
  Future<void> discardSession({
    required String memberId,
    required String sessionId,
  }) async {
    discarded.add(memberId);
    active.remove(memberId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeWorkoutSessionRepository repository;

  Widget buildApp({List<TrainingPlanEntry> plan = const []}) {
    return ProviderScope(
      overrides: [
        occurrenceBookingsProvider.overrideWith(
          (ref, occurrenceId) => Stream.value(
            _members.map((m) => _booking(m.uid)).toList(),
          ),
        ),
        membersProvider.overrideWith((ref) => Stream.value(_members)),
        exercisesProvider
            .overrideWith((ref) => Stream.value(const [_exercise])),
        trainingPlanProvider.overrideWith(
          (ref, memberId) => Stream.value(plan),
        ),
        workoutSessionRepositoryProvider.overrideWithValue(repository),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
              uid: _instructorId,
              tenantId: _tenantId,
              roles: {Role.instructor},
            ),
          ),
        ),
      ],
      child: const MaterialApp(
        home: GroupWorkoutScreen(
          occurrenceId: _occurrenceId,
          title: 'Aula de Grupo',
        ),
      ),
    );
  }

  setUp(() {
    repository = _FakeWorkoutSessionRepository();
  });

  testWidgets('mostra a turma inteira numa linha', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsWidgets);
    expect(find.text('João Martins'), findsOneWidget);
    expect(find.text('por iniciar'), findsNWidgets(2));
  });

  testWidgets('começa o treino de toda a gente de uma vez', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iniciar treino para a turma (2)'));
    await tester.pumpAndSettle();

    expect(repository.started, ['member_rita', 'member_joao']);
  });

  testWidgets('quem já estava a treinar não recomeça', (tester) async {
    // Um aluno que chegou mais cedo e começou pelo telemóvel: abrir-lhe
    // uma segunda sessão significaria não saber a qual pertence a
    // próxima série.
    repository.active['member_rita'] = WorkoutSession(
      id: 'ja_a_decorrer',
      memberId: 'member_rita',
      workoutName: 'Treino A',
      startedAt: DateTime(2026, 8, 20, 18),
      performedBy: 'member_rita',
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Iniciar para os restantes (1)'), findsOneWidget);
    await tester.tap(find.text('Iniciar para os restantes (1)'));
    await tester.pumpAndSettle();

    expect(repository.started, ['member_joao']);
  });

  testWidgets('sem sessão começada, o painel do aluno explica o que falta',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('ainda não começou'), findsOneWidget);
  });

  testWidgets('com sessão a decorrer mostra o plano do aluno selecionado',
      (tester) async {
    repository.active['member_rita'] = WorkoutSession(
      id: 'sessao_rita',
      memberId: 'member_rita',
      workoutName: 'Aula de Grupo',
      startedAt: DateTime(2026, 8, 20, 19),
      performedBy: _instructorId,
    );

    await tester.pumpWidget(buildApp(plan: const [
      TrainingPlanEntry(
        id: 'entry_1',
        memberId: 'member_rita',
        exerciseId: 'ex_supino',
        sets: 4,
        reps: '8-12',
        currentLoad: 60,
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Supino plano'), findsOneWidget);
    expect(find.textContaining('Plano: 4 × 8-12'), findsOneWidget);
  });

  testWidgets('terminar todos fecha o que tem séries e descarta o resto',
      (tester) async {
    repository.active['member_rita'] = WorkoutSession(
      id: 'com_series',
      memberId: 'member_rita',
      workoutName: 'Aula de Grupo',
      startedAt: DateTime(2026, 8, 20, 19),
      performedBy: _instructorId,
      sets: [
        SetLog(
          exerciseId: 'ex_supino',
          setNumber: 1,
          reps: 10,
          load: 60,
          completedAt: DateTime(2026, 8, 20, 19, 5),
        ),
      ],
    );
    repository.active['member_joao'] = WorkoutSession(
      id: 'sem_series',
      memberId: 'member_joao',
      workoutName: 'Aula de Grupo',
      startedAt: DateTime(2026, 8, 20, 19),
      performedBy: _instructorId,
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terminar todos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminar'));
    await tester.pumpAndSettle();

    // Um treino sem uma única série no histórico é ruído.
    expect(repository.finished, ['member_rita']);
    expect(repository.discarded, ['member_joao']);
  });
}
