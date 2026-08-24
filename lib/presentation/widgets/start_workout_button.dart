import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/training_workout.dart';
import '../screens/active_workout_screen.dart';
import 'design_system.dart';

/// Fase 11 — iniciar (ou continuar) um treino.
///
/// O mesmo componente serve os três papéis, e é deliberado: num ginásio
/// com acompanhamento, quem regista tanto pode ser o aluno como o
/// instrutor ao lado dele. A diferença fica no registo (`performedBy`),
/// não em ter dois caminhos diferentes na app.
///
/// Se já houver uma sessão em curso, o botão passa a "Continuar treino"
/// e leva à mesma — nunca abre uma segunda, porque duas sessões abertas
/// ao mesmo tempo significaria não saber a qual pertence a próxima série.
class StartWorkoutButton extends ConsumerWidget {
  const StartWorkoutButton({
    super.key,
    required this.memberId,
    this.compact = false,
    this.workout,
  });

  final String memberId;

  /// Versão de linha, para caber num cartão em vez de ocupar a largura.
  final bool compact;

  /// Quando vem preenchido, começa ESTE treino sem perguntar qual.
  /// É o botão que aparece dentro da secção de um treino no plano —
  /// aí a escolha já foi feita ao ler o cabeçalho, e voltar a
  /// perguntá-la seria repetir a pergunta que o utilizador já
  /// respondeu.
  final TrainingWorkout? workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeWorkoutSessionProvider(memberId));
    final workoutsAsync = ref.watch(memberWorkoutsProvider(memberId));
    final active = activeAsync.valueOrNull;
    final workouts = (workoutsAsync.valueOrNull ?? const <TrainingWorkout>[])
        .where((w) => w.active)
        .toList();

    // Um treino em curso ganha sempre: abrir um segundo significaria
    // não saber a qual pertence a próxima série. Nesse caso o botão da
    // secção continua a levar ao treino que está a decorrer.
    final target = workout;
    if (active == null && target != null) {
      return _button(
        context,
        'Iniciar este treino',
        Icons.play_arrow,
        () => _start(context, ref, target),
      );
    }

    // Sem plano não há o que treinar. Dizê-lo é melhor do que um botão
    // que abre um ecrã vazio.
    if (active == null && workouts.isEmpty) {
      if (compact) return const SizedBox.shrink();
      return const PanelCard(
        child: Text(
          'Ainda não tens plano de treino. Fala com o teu instrutor.',
          style: TextStyle(color: AppColors.mute, fontSize: 12),
        ),
      );
    }

    final label = active != null ? 'Continuar treino' : 'Iniciar treino';
    final icon = active != null ? Icons.play_circle_outline : Icons.play_arrow;

    return _button(
      context,
      label,
      icon,
      () => _open(context, ref, active, workouts),
    );
  }

  Widget _button(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    if (compact) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    dynamic active,
    List<TrainingWorkout> workouts,
  ) async {
    if (active != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ActiveWorkoutScreen(memberId: memberId, session: active),
        ),
      );
      return;
    }

    // Um treino só: não vale a pena perguntar qual.
    final chosen = workouts.length == 1
        ? workouts.first
        : await showModalBottomSheet<TrainingWorkout>(
            context: context,
            backgroundColor: AppColors.panel,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  const SectionLabel('Que treino vais fazer?'),
                  const SizedBox(height: 8),
                  for (final workout in workouts)
                    ListTile(
                      leading: const IconBox(Icons.fitness_center_outlined),
                      title: Text(workout.name),
                      onTap: () => Navigator.of(sheetContext).pop(workout),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );

    if (chosen == null || !context.mounted) return;
    await _start(context, ref, chosen);
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    TrainingWorkout chosen,
  ) async {
    final performedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (performedBy == null) return;

    try {
      final sessionId =
          await ref.read(workoutSessionRepositoryProvider).startSession(
                memberId: memberId,
                workoutId: chosen.id,
                workoutName: chosen.name,
                performedBy: performedBy,
              );
      // Lê a sessão recém-criada em vez de a construir à mão: o
      // `startedAt` é do servidor, e uma cópia local teria outra hora.
      final session =
          await ref.read(activeWorkoutSessionProvider(memberId).future);
      if (!context.mounted) return;
      if (session == null || session.id != sessionId) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ActiveWorkoutScreen(memberId: memberId, session: session),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível iniciar o treino. Tenta outra vez.'))),
      );
    }
  }
}
