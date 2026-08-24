import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/load_history_entry.dart';
import 'package:gym_saas/presentation/screens/load_evolution_screen.dart';
import 'package:gym_saas/repositories/load_history_repository.dart';

const _memberId = 'member_1';
const _exerciseId = 'ex_supino';

/// Reportado pelo Carlos a testar: "no ver a evolução de carga não
/// deveria aparecer as várias séries todas — apenas a carga mais alta e
/// repetições de cada exercício naquele dia".
///
/// O registo ao vivo (Fase 11) escreve um registo POR SÉRIE: quatro
/// séries num dia enchiam a evolução com quatro linhas onde a pergunta
/// é sempre a mesma.
class _FakeLoadHistoryRepository implements LoadHistoryRepository {
  _FakeLoadHistoryRepository(this.entries);

  final List<LoadHistoryEntry> entries;

  @override
  Stream<List<LoadHistoryEntry>> watchHistory({
    required String memberId,
    required String exerciseId,
  }) =>
      Stream.value(entries);

  @override
  Future<void> addEntry({
    required String memberId,
    required String exerciseId,
    required double load,
    required int reps,
    required String recordedBy,
  }) =>
      throw UnimplementedError();
}

LoadHistoryEntry _entry({
  required String id,
  required DateTime at,
  required double load,
  required int reps,
}) {
  return LoadHistoryEntry(
    id: id,
    memberId: _memberId,
    exerciseId: _exerciseId,
    load: load,
    reps: reps,
    recordedAt: at,
    recordedBy: _memberId,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  final hoje = DateTime(2026, 8, 20, 19);
  final semanaPassada = DateTime(2026, 8, 13, 19);

  // Um dia de treino real: quatro séries, a subir e depois a cair com o
  // cansaço. A melhor é 62.5 kg × 8.
  final history = [
    _entry(
        id: '4', at: hoje.add(const Duration(minutes: 9)), load: 60, reps: 6),
    _entry(
        id: '3', at: hoje.add(const Duration(minutes: 6)), load: 62.5, reps: 8),
    _entry(
        id: '2', at: hoje.add(const Duration(minutes: 3)), load: 60, reps: 10),
    _entry(id: '1', at: hoje, load: 60, reps: 10),
    _entry(id: '0', at: semanaPassada, load: 55, reps: 10),
  ];

  Widget buildApp(List<LoadHistoryEntry> entries) {
    return ProviderScope(
      overrides: [
        loadHistoryRepositoryProvider
            .overrideWithValue(_FakeLoadHistoryRepository(entries)),
      ],
      child: const MaterialApp(
        home: LoadEvolutionScreen(
          memberId: _memberId,
          exerciseId: _exerciseId,
          exerciseName: 'Supino plano',
        ),
      ),
    );
  }

  testWidgets('uma linha por DIA, não uma por série', (tester) async {
    await tester.pumpWidget(buildApp(history));
    await tester.pumpAndSettle();

    // Cinco registos, dois dias de treino.
    expect(find.text('1 série registada'), findsOneWidget);
    expect(find.text('4 séries registadas'), findsOneWidget);
  });

  testWidgets('mostra a melhor série do dia, não a última', (tester) async {
    // A última do dia foi 60 kg × 6 (cansaço); a que representa o dia é
    // 62.5 × 8.
    await tester.pumpWidget(buildApp(history));
    await tester.pumpAndSettle();

    expect(find.text('62.5 kg × 8'), findsWidgets);
    expect(find.text('60 kg × 6'), findsNothing);
  });

  testWidgets('empate na carga resolve-se pelas repetições', (tester) async {
    final empate = [
      _entry(
          id: 'b', at: hoje.add(const Duration(minutes: 3)), load: 60, reps: 6),
      _entry(id: 'a', at: hoje, load: 60, reps: 12),
    ];
    await tester.pumpWidget(buildApp(empate));
    await tester.pumpAndSettle();

    expect(find.text('60 kg × 12'), findsWidgets);
  });

  testWidgets('o ganho é contado entre dias, não entre séries', (tester) async {
    await tester.pumpWidget(buildApp(history));
    await tester.pumpAndSettle();

    // 55 kg na semana passada, 62.5 hoje.
    expect(find.text('+7.5 kg'), findsOneWidget);
  });

  testWidgets('com um único dia não inventa comparação', (tester) async {
    await tester.pumpWidget(buildApp([history.first]));
    await tester.pumpAndSettle();

    expect(find.textContaining('desde'), findsNothing);
  });
}
