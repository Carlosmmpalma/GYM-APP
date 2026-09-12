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
import 'package:gym_saas/domain/entities/training_workout.dart';
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
  category: 'Peito',
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

  /// Que treino do split foi escolhido para cada arranque.
  final List<String?> startedWorkoutIds = [];

  /// As trocas de treino pedidas depois da sessão já aberta.
  final List<({String memberId, String workoutId})> workoutChanges = [];

  @override
  Future<void> changeWorkout({
    required String memberId,
    required String sessionId,
    required String workoutId,
    required String workoutName,
  }) async {
    workoutChanges.add((memberId: memberId, workoutId: workoutId));
    final current = active[memberId];
    if (current != null) {
      active[memberId] = WorkoutSession(
        id: current.id,
        memberId: current.memberId,
        workoutId: workoutId,
        workoutName: workoutName,
        startedAt: current.startedAt,
        performedBy: current.performedBy,
        sets: current.sets,
      );
    }
  }

  @override
  Future<String> startSession({
    required String memberId,
    required String? workoutId,
    required String workoutName,
    required String performedBy,
  }) async {
    started.add(memberId);
    startedWorkoutIds.add(workoutId);
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

const _workoutA = TrainingWorkout(
  id: 'workout_a',
  memberId: 'qualquer',
  name: 'Treino A — Superiores',
);

/// A mesma prescrição, mas presa ao Treino A — para os testes em que a
/// sessão tem treino associado e o painel filtra por ele.
const _entryDoTreinoA = TrainingPlanEntry(
  id: 'entry_1',
  memberId: 'qualquer',
  exerciseId: 'ex_supino',
  sets: 4,
  reps: '8-12',
  currentLoad: 60,
  workoutId: 'workout_a',
);

/// A prescrição usada pelos testes da vista por exercício.
const _entry = TrainingPlanEntry(
  id: 'entry_1',
  memberId: 'qualquer',
  exerciseId: 'ex_supino',
  sets: 4,
  reps: '8-12',
  currentLoad: 60,
);

WorkoutSession _session(String memberId) => WorkoutSession(
      id: 'sessao_$memberId',
      memberId: memberId,
      workoutName: 'Aula de Grupo',
      startedAt: DateTime(2026, 8, 20, 19),
      performedBy: _instructorId,
    );

void main() {
  late _FakeWorkoutSessionRepository repository;

  Widget buildApp({
    List<TrainingPlanEntry> plan = const [],
    List<TrainingWorkout> workouts = const [_workoutA],
  }) {
    return ProviderScope(
      overrides: [
        occurrenceBookingsProvider.overrideWith(
          (ref, occurrenceId) => Stream.value(
            _members.map((m) => _booking(m.uid)).toList(),
          ),
        ),
        membersProvider.overrideWith((ref) => Stream.value(_members)),
        // O ecrã pede só os exercícios do plano do aluno, não a
        // biblioteca inteira.
        exercisesByIdsProvider.overrideWith(
          (ref, key) async => {_exercise.id: _exercise},
        ),
        trainingPlanProvider.overrideWith(
          (ref, memberId) => Stream.value(plan),
        ),
        // O arranque passou a perguntar QUE treino cada um faz — sem
        // treinos no plano, a folha não deixa começar (e diz porquê).
        memberWorkoutsProvider.overrideWith(
          (ref, memberId) => Stream.value(workouts),
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

  /// O botão de arranque abre uma folha a perguntar que treino cada um
  /// vai fazer; só depois é que as sessões abrem.
  ///
  /// O botão da barra é procurado pelo tipo e não pelo texto: o rótulo
  /// muda conforme quantos faltam ("Iniciar treino para a turma (2)" /
  /// "Iniciar para os restantes (1)"), e a mesma frase aparece no
  /// estado vazio do painel.
  Future<void> iniciarTurma(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Começar ('));
    await tester.pumpAndSettle();
  }

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

    await iniciarTurma(tester);

    expect(repository.started, ['member_rita', 'member_joao']);
    // E cada sessão fica ligada ao treino escolhido — sem isso, o
    // painel mostrava o plano inteiro e o histórico não sabia o que
    // foi feito.
    expect(repository.startedWorkoutIds, ['workout_a', 'workout_a']);
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
    await iniciarTurma(tester);

    // A folha lista a turma toda (é o instrutor que vê quem já está a
    // treinar), mas só abre sessão a quem não tem uma a decorrer.
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

  group('vista por exercício', () {
    // Num aula de grupo o instrutor não pensa "agora a Ana" — chama o
    // exercício e toda a gente o faz. Esta vista põe o exercício no
    // topo e a turma em coluna.
    Future<void> abrirPorExercicio(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.fitness_center_outlined));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra o exercício e quantos alunos o fazem', (tester) async {
      repository.active[_members.first.uid] = _session(_members.first.uid);
      await tester.pumpWidget(buildApp(plan: [_entry]));
      await tester.pumpAndSettle();

      await abrirPorExercicio(tester);

      // Todos os inscritos têm o mesmo plano neste teste.
      expect(find.text('Toda a turma (${_members.length})'), findsOneWidget);
      expect(find.text(_exercise.name), findsWidgets);
    });

    testWidgets('lista a turma toda dentro do exercício', (tester) async {
      // É a diferença que interessa: os nomes aparecem TODOS na mesma
      // página, em vez de um de cada vez.
      for (final m in _members) {
        repository.active[m.uid] = _session(m.uid);
      }
      await tester.pumpWidget(buildApp(plan: [_entry]));
      await tester.pumpAndSettle();

      await abrirPorExercicio(tester);

      for (final member in _members) {
        expect(find.text(member.name), findsWidgets,
            reason: '${member.name} devia estar na página do exercício');
      }
    });

    testWidgets('quem ainda não começou aparece assinalado, não escondido',
        (tester) async {
      // Esconder deixava o instrutor a pensar que a pessoa não tinha o
      // exercício, quando o que falta é a sessão.
      await tester.pumpWidget(buildApp(plan: [_entry]));
      await tester.pumpAndSettle();

      await abrirPorExercicio(tester);

      expect(find.text('por iniciar'), findsWidgets);
      expect(find.textContaining('Ainda não começou'), findsWidgets);
    });

    testWidgets('sem planos, explica em vez de mostrar uma página vazia',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await abrirPorExercicio(tester);

      expect(find.text('Sem exercícios prescritos'), findsOneWidget);
    });

    testWidgets('volta a "por aluno" e mostra um de cada vez', (tester) async {
      repository.active[_members.first.uid] = _session(_members.first.uid);
      await tester.pumpWidget(buildApp(plan: [_entry]));
      await tester.pumpAndSettle();

      await abrirPorExercicio(tester);
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      expect(find.text('Toda a turma (${_members.length})'), findsNothing);
    });
  });

  group('escolher o treino de cada aluno', () {
    // O arranque em grupo abria sessões sem treino associado
    // (`workoutId: null`): o painel mostrava TODOS os exercícios do
    // plano — quem tem um split A/B/C via vinte em vez dos sete de hoje
    // — e o histórico ficava sem saber o que foi feito.
    const workoutB = TrainingWorkout(
      id: 'workout_b',
      memberId: 'qualquer',
      name: 'Treino B — Inferiores',
    );

    testWidgets('pergunta antes de começar', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      // `SectionLabel` escreve em maiúsculas.
      expect(find.text('QUE TREINO VAI CADA UM FAZER?'), findsOneWidget);
      // Ainda não abriu sessão nenhuma.
      expect(repository.started, isEmpty);
    });

    testWidgets('grava o treino escolhido em cada sessão', (tester) async {
      await tester.pumpWidget(
        buildApp(workouts: const [_workoutA, workoutB]),
      );
      await tester.pumpAndSettle();

      await iniciarTurma(tester);

      // O primeiro treino ativo vem pré-escolhido.
      expect(repository.startedWorkoutIds, ['workout_a', 'workout_a']);
    });

    testWidgets('sem treinos no plano, diz porquê e não começa',
        (tester) async {
      // Abrir uma sessão sem exercícios é uma linha no histórico que
      // não diz nada e que alguém tem de ir fechar à mão.
      await tester.pumpWidget(buildApp(workouts: const []));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Sem treinos no plano'), findsWidgets);
      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Começar (0 de 2)'),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('o painel mostra só os exercícios do treino escolhido',
        (tester) async {
      // O filtro por `workoutId` já existia no painel; o que faltava
      // era a sessão ter um.
      repository.active['member_rita'] = WorkoutSession(
        id: 'sessao_rita',
        memberId: 'member_rita',
        workoutName: 'Treino A — Superiores',
        workoutId: 'workout_a',
        startedAt: DateTime(2026, 8, 20, 19),
        performedBy: _instructorId,
      );

      await tester.pumpWidget(buildApp(plan: const [
        TrainingPlanEntry(
          id: 'entry_a',
          memberId: 'member_rita',
          exerciseId: 'ex_supino',
          sets: 4,
          reps: '8-12',
          workoutId: 'workout_a',
        ),
        TrainingPlanEntry(
          id: 'entry_b',
          memberId: 'member_rita',
          exerciseId: 'ex_agachamento',
          sets: 4,
          reps: '10',
          workoutId: 'workout_b',
        ),
      ]));
      await tester.pumpAndSettle();

      // Só o exercício do Treino A. O do B é do outro dia do split.
      expect(find.text(_exercise.name), findsWidgets);
      expect(find.text('ex_agachamento'), findsNothing);
    });

    testWidgets('o cabeçalho diz que treino está a ser feito', (tester) async {
      // Com um split A/B/C, saber QUAL está a decorrer é metade da
      // informação — e antes não aparecia em lado nenhum.
      repository.active['member_rita'] = WorkoutSession(
        id: 'sessao_rita',
        memberId: 'member_rita',
        workoutName: 'Treino B — Inferiores',
        workoutId: 'workout_b',
        startedAt: DateTime(2026, 8, 20, 19),
        performedBy: _instructorId,
      );

      await tester.pumpWidget(buildApp(plan: const [
        TrainingPlanEntry(
          id: 'entry_b',
          memberId: 'member_rita',
          exerciseId: 'ex_supino',
          sets: 4,
          reps: '10',
          workoutId: 'workout_b',
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Treino B — Inferiores'), findsWidgets);
    });
  });

  group('trocar o treino depois de arrancar', () {
    const workoutB = TrainingWorkout(
      id: 'workout_b',
      memberId: 'qualquer',
      name: 'Treino B — Inferiores',
    );

    WorkoutSession sessaoDaRita({List<SetLog> sets = const []}) =>
        WorkoutSession(
          id: 'sessao_rita',
          memberId: 'member_rita',
          workoutId: 'workout_a',
          workoutName: 'Treino A — Superiores',
          startedAt: DateTime(2026, 8, 20, 19),
          performedBy: _instructorId,
          sets: sets,
        );

    testWidgets('troca enquanto não há séries registadas', (tester) async {
      // Enganar-se numa linha da folha de arranque é fácil quando há
      // quatro ou cinco nomes. Sem isto, a única saída era terminar a
      // sessão e recomeçar — com a aula a decorrer.
      repository.active['member_rita'] = sessaoDaRita();

      await tester.pumpWidget(
        buildApp(
          // A prescrição TEM de pertencer ao treino da sessão, senão o
          // painel mostra o estado vazio — e é assim que deve ser.
          plan: const [_entryDoTreinoA],
          workouts: const [_workoutA, workoutB],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trocar treino').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(workoutB.name).last);
      await tester.pumpAndSettle();

      expect(repository.workoutChanges, hasLength(1));
      expect(repository.workoutChanges.first.workoutId, 'workout_b');
    });

    testWidgets('com séries já registadas, deixa de estar disponível',
        (tester) async {
      // As séries feitas pertencem a exercícios do treino antigo:
      // trocar por baixo delas deixava-as fora da lista mas a contar
      // nos totais.
      repository.active['member_rita'] = sessaoDaRita(sets: [
        SetLog(
          exerciseId: 'ex_supino',
          setNumber: 1,
          reps: 10,
          load: 60,
          completedAt: DateTime(2026, 8, 20, 19, 5),
        ),
      ]);

      await tester.pumpWidget(
        buildApp(
          plan: const [_entryDoTreinoA],
          workouts: const [_workoutA, workoutB],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trocar treino'), findsNothing);
    });
  });
}
