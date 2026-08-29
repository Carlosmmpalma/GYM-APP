import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/training_plan_entry.dart';
import '../../domain/entities/training_workout.dart';
import '../widgets/design_system.dart';
import '../widgets/start_workout_button.dart';
import 'exercise_video_screen.dart';
import 'load_evolution_screen.dart';
import 'workout_history_screen.dart';

/// Fase 8 (UC03 — "série/reps/carga + vídeo por exercício") — "O meu
/// plano": o Aluno vê sempre a carga mais recente (nunca o histórico
/// diretamente aqui); tocar num exercício oferece as duas ações do
/// mockup — ver o vídeo demonstrativo ou a evolução da carga.
///
/// **Agrupado por treino desde que os treinos existem.** A Fase 11
/// acrescentou "Treino A — Costas" / "Treino B — Peito" ao editor do
/// instrutor, mas este ecrã continuou a mostrar uma lista corrida de
/// exercícios: o aluno via 18 exercícios seguidos sem saber quais eram
/// os de hoje. O agrupamento não é decoração — é a informação que
/// responde à única pergunta que traz alguém a este ecrã: "o que é que
/// eu faço hoje?".
class MyTrainingPlanScreen extends ConsumerWidget {
  const MyTrainingPlanScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(trainingPlanProvider(memberId));
    final workoutsAsync = ref.watch(memberWorkoutsProvider(memberId));
    // Só os exercícios deste plano, não a biblioteca inteira: um aluno
    // precisa de meia dúzia de nomes e estava a ler 61 documentos (e a
    // crescer com a biblioteca, que é a métrica errada).
    final exercisesAsync = ref.watch(
      exercisesByIdsProvider(
        exerciseKeyFor(
          (planAsync.valueOrNull ?? const <TrainingPlanEntry>[])
              .map((entry) => entry.exerciseId),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('O meu plano'),
        actions: [
          IconButton(
            tooltip: 'Treinos que já fiz',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkoutHistoryScreen(memberId: memberId),
              ),
            ),
          ),
        ],
      ),
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

          final exercisesById =
              exercisesAsync.valueOrNull ?? const <String, Exercise>{};
          final workouts =
              (workoutsAsync.valueOrNull ?? const <TrainingWorkout>[])
                  .where((w) => w.active)
                  .toList();

          // Exercícios sem treino: ou o plano é anterior aos treinos
          // existirem, ou o instrutor ainda não os arrumou. Aparecem no
          // fim, com um título que diz o que são — esconder era perder
          // exercícios prescritos.
          final orphans = entries.where((e) => e.workoutId == null).toList()
            ..sort((a, b) => a.position.compareTo(b.position));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final workout in workouts)
                _WorkoutSection(
                  memberId: memberId,
                  workout: workout,
                  entries:
                      entries.where((e) => e.workoutId == workout.id).toList()
                        ..sort((a, b) => a.position.compareTo(b.position)),
                  exercisesById: exercisesById,
                ),
              if (orphans.isNotEmpty) ...[
                SectionLabel(
                  workouts.isEmpty ? 'O teu plano' : 'Outros exercícios',
                ),
                const SizedBox(height: 8),
                for (final entry in orphans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ExerciseRow(
                      memberId: memberId,
                      entry: entry,
                      exercise: exercisesById[entry.exerciseId],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              // A linha de ajuda do mockup: é o que explica que os
              // cartões são tocáveis — sem ela, as duas ações
              // (vídeo/evolução) ficavam escondidas atrás de um toque
              // que ninguém sabe que existe.
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Toca num exercício para ver o vídeo demonstrativo ou a '
                  'evolução da carga',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.dim, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Um treino do plano, como o aluno o vê: o nome que o instrutor lhe
/// deu, as instruções, os exercícios pela ordem em que se fazem, e o
/// botão para o começar.
class _WorkoutSection extends StatelessWidget {
  const _WorkoutSection({
    required this.memberId,
    required this.workout,
    required this.entries,
    required this.exercisesById,
  });

  final String memberId;
  final TrainingWorkout workout;
  final List<TrainingPlanEntry> entries;
  final Map<String, Exercise> exercisesById;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                workout.name.toUpperCase(),
                style: AppTheme.display(fontSize: 16),
              ),
            ),
            Text(
              entries.length == 1
                  ? '1 exercício'
                  : '${entries.length} exercícios',
              style: const TextStyle(color: AppColors.mute, fontSize: 11),
            ),
          ],
        ),
        if (workout.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            workout.notes,
            style: const TextStyle(
                color: AppColors.mute, fontSize: 12, height: 1.4),
          ),
        ],
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const PanelCard(
            child: Text(
              'Este treino ainda não tem exercícios.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          )
        else ...[
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ExerciseRow(
                memberId: memberId,
                entry: entry,
                exercise: exercisesById[entry.exerciseId],
              ),
            ),
          const SizedBox(height: 2),
          StartWorkoutButton(
            memberId: memberId,
            workout: workout,
            compact: true,
          ),
        ],
        const SizedBox(height: 24),
      ],
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
    required this.memberId,
    required this.entry,
    required this.exercise,
  });

  final String memberId;
  final TrainingPlanEntry entry;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) {
    final name = exercise?.name ?? entry.exerciseId;
    return PanelCard(
      onTap: () => _showActions(context),
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
                  '${entry.sets} séries × ${entry.reps} reps'
                  '${entry.restSeconds != null ? ' · ${entry.restSeconds}s descanso' : ''}',
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.notes,
                    style: const TextStyle(
                        color: AppColors.dim, fontSize: 11, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.currentLoad != null ? '${entry.currentLoad} kg' : '—',
            style: AppTheme.display(fontSize: 15, color: AppColors.red),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
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
