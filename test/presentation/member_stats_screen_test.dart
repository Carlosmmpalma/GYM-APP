import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/assessment.dart';
import 'package:gym_saas/domain/entities/exercise.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/workout_session.dart';
import 'package:gym_saas/presentation/screens/member_stats_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

const _member = MemberSummary(
  uid: 'member_1',
  memberNumber: '000001',
  name: 'Rita Ferreira',
  active: true,
);

const _exercises = [
  Exercise(
    id: 'ex_supino',
    name: 'Supino plano',
    description: '',
    muscleGroup: 'Peito',
  ),
  Exercise(
    id: 'ex_agachamento',
    name: 'Agachamento',
    description: '',
    muscleGroup: 'Pernas',
  ),
];

WorkoutSession _session({
  required String id,
  required DateTime startedAt,
  required List<SetLog> sets,
}) {
  return WorkoutSession(
    id: id,
    memberId: _member.uid,
    workoutName: 'Treino A',
    startedAt: startedAt,
    finishedAt: startedAt.add(const Duration(hours: 1)),
    performedBy: _member.uid,
    sets: sets,
  );
}

/// O ecrã que faltava a quem acompanha: o histórico dizia o que se fez
/// no dia 12; isto diz como é que a pessoa está.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Widget buildApp({
    List<WorkoutSession> sessions = const [],
    List<Assessment> assessments = const [],
  }) {
    return ProviderScope(
      overrides: [
        workoutSessionsProvider
            .overrideWith((ref, memberId) => Stream.value(sessions)),
        assessmentsProvider
            .overrideWith((ref, memberId) => Stream.value(assessments)),
        exercisesProvider.overrideWith((ref) => Stream.value(_exercises)),
      ],
      child: const MaterialApp(home: MemberStatsScreen(member: _member)),
    );
  }

  testWidgets('sem treinos, explica de onde vêm os números', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Ainda sem treinos registados'), findsOneWidget);
  });

  testWidgets('mostra consistência, equilíbrio e força', (tester) async {
    final agora = DateTime.now();
    await tester.pumpWidget(buildApp(sessions: [
      _session(
        id: 's1',
        startedAt: agora.subtract(const Duration(days: 2)),
        sets: [
          SetLog(
            exerciseId: 'ex_supino',
            setNumber: 1,
            reps: 5,
            load: 80,
            completedAt: agora,
          ),
          SetLog(
            exerciseId: 'ex_agachamento',
            setNumber: 1,
            reps: 8,
            load: 100,
            completedAt: agora,
          ),
        ],
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('CONSISTÊNCIA'), findsOneWidget);
    expect(find.text('EQUILÍBRIO'), findsOneWidget);

    // Grupos musculares, a partir da biblioteca de exercícios.
    expect(find.text('Peito'), findsOneWidget);
    expect(find.text('Pernas'), findsOneWidget);

    // A secção da força fica abaixo da dobra no ecrã de teste.
    await tester.scrollUntilVisible(
      find.text('Supino plano'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('FORÇA'), findsOneWidget);
    // 1RM estimado: 80 × (1 + 5/30) = 93,3 kg.
    expect(find.text('93.3 kg'), findsOneWidget);
  });

  testWidgets('um exercício sem carga aparece sem 1RM inventado',
      (tester) async {
    final agora = DateTime.now();
    await tester.pumpWidget(buildApp(sessions: [
      _session(
        id: 's1',
        startedAt: agora.subtract(const Duration(days: 1)),
        sets: [
          SetLog(
            exerciseId: 'ex_prancha',
            setNumber: 1,
            reps: 45,
            completedAt: agora,
          ),
        ],
      ),
    ]));
    await tester.pumpAndSettle();

    // Sem carga não há 1RM — e inventar um seria pior do que o traço.
    await tester.scrollUntilVisible(
      find.text('ex_prancha'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('mostra a variação da composição corporal desde a primeira',
      (tester) async {
    final agora = DateTime.now();
    Assessment avaliacao({
      required String id,
      required DateTime createdAt,
      required double peso,
    }) {
      return Assessment(
        id: id,
        memberId: _member.uid,
        instructorId: 'staff_1',
        createdAt: createdAt,
        idade: 30,
        peso: peso,
        altura: 1.70,
        percentMassaGorda: 20,
        massaMuscular: 30,
        gorduraVisceral: 5,
        metabolismoBasal: 1500,
        percentAgua: 55,
        idadeMetabolica: 28,
        pressaoArterial: '120/80',
        perimetroCintura: 80,
        perimetroAbdominal: 85,
        forcaMS: 'Bom',
        forcaMI: 'Bom',
        forcaCore: 'Bom',
        flexibilidade: 'Bom',
        resistencia: 'Bom',
      );
    }

    await tester.pumpWidget(buildApp(
      sessions: const [],
      assessments: [
        // A lista chega da mais recente para a mais antiga.
        avaliacao(id: 'a2', createdAt: agora, peso: 72),
        avaliacao(
          id: 'a1',
          createdAt: agora.subtract(const Duration(days: 90)),
          peso: 75,
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Peso'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('72.0 kg'), findsOneWidget);
    // Perdeu 3 kg — mostrado sem juízo de valor na cor: ganhar peso é o
    // objetivo de quem treina para massa.
    expect(find.text('-3.0 kg'), findsOneWidget);
  });
}
