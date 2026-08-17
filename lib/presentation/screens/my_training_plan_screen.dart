import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/training_plan_entry.dart';
import 'exercise_video_screen.dart';
import 'load_evolution_screen.dart';

/// Fase 8 (UC03 — "série/reps/carga + vídeo por exercício") — "O meu
/// plano": o Aluno vê sempre a carga mais recente (nunca o histórico
/// diretamente aqui); tocar num exercício oferece as duas ações do
/// mockup — ver o vídeo demonstrativo ou a evolução da carga.
class MyTrainingPlanScreen extends ConsumerWidget {
  const MyTrainingPlanScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(trainingPlanProvider(memberId));
    final exercisesAsync = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('O meu plano')),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sem plano atribuído. Fala com o teu instrutor para '
                  'começares o teu plano de treino.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final exercisesById = <String, Exercise>{
            for (final e in exercisesAsync.valueOrNull ?? const <Exercise>[])
              e.id: e,
          };
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final exercise = exercisesById[entry.exerciseId];
              return Card(
                child: ListTile(
                  title: Text(exercise?.name ?? entry.exerciseId),
                  subtitle: Text(
                    '${entry.sets} séries × ${entry.reps} reps — '
                    '${entry.currentLoad != null ? '${entry.currentLoad} kg' : '—'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showActions(context, entry, exercise),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    TrainingPlanEntry entry,
    Exercise? exercise,
  ) async {
    // "Toca num exercício para ver o vídeo demonstrativo ou a
    // evolução da carga" — exatamente as duas ações do mockup.
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exercise?.hasVideo ?? false)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Ver vídeo demonstrativo'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExerciseVideoScreen(exercise: exercise!),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.show_chart),
              title: const Text('Ver evolução da carga'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LoadEvolutionScreen(
                      memberId: memberId,
                      exerciseId: entry.exerciseId,
                      exerciseName: exercise?.name ?? entry.exerciseId,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
