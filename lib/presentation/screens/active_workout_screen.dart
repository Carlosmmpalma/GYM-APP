import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/workout_session.dart';
import '../widgets/design_system.dart';
import '../widgets/exercise_logger.dart';

/// Fase 11 — o registo de treino ao vivo.
///
/// É o ecrã onde um ginásio com acompanhamento acontece: o aluno (ou o
/// instrutor ao lado dele) confirma cada série à medida que a faz.
///
/// O desenho segue o que as apps da área convergiram (Hevy, Strong,
/// Trainerize): uma linha por série, com os campos já preenchidos pela
/// prescrição, e — a parte que faz a diferença — **o que foi feito da
/// última vez**, em cinzento, ao lado. É essa referência que torna a
/// progressão possível: ninguém se lembra do peso de há uma semana, e
/// sem ela o registo vira burocracia em vez de ferramenta.
///
/// Confirmar uma série é um toque. Enganou-se, "anular" tira a última —
/// porque a correção mais frequente a registar ao vivo é ter confirmado
/// uma série a mais, e isso não pode exigir abrir um ecrã de edição.
/// Para o resto — 6 kg escritos em vez de 60 na segunda de quatro
/// séries — toca-se na série já confirmada e corrige-se ali, incluindo
/// o registo de carga que ela criou.
class ActiveWorkoutScreen extends ConsumerWidget {
  const ActiveWorkoutScreen({
    super.key,
    required this.memberId,
    required this.session,
  });

  final String memberId;
  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(trainingPlanProvider(memberId));
    final exercisesAsync = ref.watch(exercisesProvider);
    // A sessão ao vivo: `session` é a fotografia de quando o ecrã abriu,
    // e ficaria desatualizada a cada série confirmada.
    final liveSession =
        ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull ??
            session;

    return Scaffold(
      appBar: AppBar(
        title: Text(liveSession.workoutName),
        actions: [
          TextButton(
            onPressed: () => _finish(context, ref, liveSession),
            child: const Text('Terminar'),
          ),
        ],
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (entries) {
          final exercisesById = <String, Exercise>{
            for (final e in exercisesAsync.valueOrNull ?? const <Exercise>[])
              e.id: e,
          };

          final planned = liveSession.workoutId == null
              ? entries
              : entries
                  .where((e) => e.workoutId == liveSession.workoutId)
                  .toList();

          if (planned.isEmpty) {
            return const EmptyState(
              icon: Icons.fitness_center_outlined,
              title: 'Treino sem exercícios',
              message: 'Este treino do plano ainda não tem exercícios. '
                  'Pede ao instrutor para os acrescentar.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SessionSummary(session: liveSession),
              const SizedBox(height: 20),
              for (final entry in planned) ...[
                ExerciseLogger(
                  key: ValueKey(entry.id),
                  memberId: memberId,
                  sessionId: liveSession.id,
                  entry: entry,
                  exercise: exercisesById[entry.exerciseId],
                  done: liveSession.setsFor(entry.exerciseId),
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _finish(
      BuildContext context, WidgetRef ref, WorkoutSession live) async {
    if (live.sets.isEmpty) {
      // Terminar sem nada registado guardaria uma sessão vazia no
      // histórico, que só faz ruído. Oferecer descartar é o que a pessoa
      // quer nesse caso.
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Treino sem séries'),
          content: const Text(
            'Ainda não registaste nenhuma série. Queres descartar este '
            'treino em vez de o guardar?',
            style: TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Continuar a treinar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (discard != true || !context.mounted) return;
      await ref.read(workoutSessionRepositoryProvider).discardSession(
            memberId: memberId,
            sessionId: live.id,
          );
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    try {
      await ref.read(workoutSessionRepositoryProvider).finishSession(
            memberId: memberId,
            sessionId: live.id,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treino registado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível terminar. Tenta outra vez.'))),
      );
    }
  }
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final volume = session.totalVolume;
    return PanelCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Em curso'),
                const SizedBox(height: 4),
                Text(
                  '${session.sets.length} série(s) · ${session.totalReps} reps',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          if (volume > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${volume.toStringAsFixed(0)} kg',
                    style: AppTheme.display(fontSize: 18)),
                const Text('volume total',
                    style: TextStyle(color: AppColors.mute, fontSize: 10)),
              ],
            ),
        ],
      ),
    );
  }
}
