import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/training_plan_entry.dart';
import '../widgets/design_system.dart';
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
        error: (error, stack) => ErrorState(error: error),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.assignment_outlined,
              title: 'Sem plano de treino',
              message: 'O teu plano é montado pelo instrutor: exercícios, '
                  'séries, repetições e a carga de cada um. Fala com ele '
                  'para começares.',
            );
          }
          final exercisesById = <String, Exercise>{
            for (final e in exercisesAsync.valueOrNull ?? const <Exercise>[])
              e.id: e,
          };
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            // +1 pela linha de ajuda no fim: o mockup tem-na, e é o que
            // explica que os cards são tocáveis — sem ela, as duas ações
            // (vídeo/evolução) ficavam escondidas atrás de um toque que
            // ninguém sabe que existe.
            itemCount: entries.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == entries.length) {
                return const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Toca num exercício para ver o vídeo demonstrativo ou a '
                    'evolução da carga',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.dim, fontSize: 11, height: 1.4),
                  ),
                );
              }
              final entry = entries[index];
              final exercise = exercisesById[entry.exerciseId];
              return _ExerciseRow(
                name: exercise?.name ?? entry.exerciseId,
                detail: '${entry.sets} séries × ${entry.reps} reps',
                load:
                    entry.currentLoad != null ? '${entry.currentLoad} kg' : '—',
                onTap: () => _showActions(context, entry, exercise),
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

/// A linha do mockup: `IconBox` com ▶ à esquerda, nome + séries/reps no
/// meio, e a carga em Oswald vermelho itálico à direita. A carga é o
/// número que o Aluno vem cá procurar — é o único elemento da linha com
/// destaque tipográfico, e era o que antes estava enterrado no meio do
/// subtítulo.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.name,
    required this.detail,
    required this.load,
    required this.onTap,
  });

  final String name;
  final String detail;
  final String load;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      onTap: onTap,
      child: Row(
        children: [
          const IconBox(Icons.play_arrow_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(load,
              style: AppTheme.display(fontSize: 15, color: AppColors.red)),
        ],
      ),
    );
  }
}
