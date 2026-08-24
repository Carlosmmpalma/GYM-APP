import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/workout_session.dart';
import '../widgets/design_system.dart';
import '../widgets/exercise_logger.dart';

/// Treinar com a turma toda — o instrutor a dar uma aula de grupo.
///
/// O registo de treino que existia era para uma pessoa de cada vez:
/// abrir a ficha do aluno, iniciar, registar, terminar, voltar atrás,
/// e outra vez para o seguinte. Numa aula de dez isso é impossível de
/// fazer com o telemóvel na mão enquanto se dá a aula — e o resultado
/// prático era não se registar nada.
///
/// O modelo é o que os softwares de box/estúdio usam para a mesma
/// situação (Wodify, SugarWOD, PushPress, e o "group training" do
/// Trainerize): **parte-se da AULA, não do aluno**. Vê-se a turma
/// inteira numa linha, começa-se para todos de uma vez, salta-se entre
/// pessoas com um toque, e no fim fecha-se tudo junto.
///
/// Por baixo continuam a ser sessões individuais — uma por aluno, com o
/// nome da aula. Isso é deliberado: o histórico, as estatísticas e a
/// evolução da carga de cada um continuam a funcionar exatamente como
/// antes, sem nenhum conceito novo de "sessão partilhada" que depois
/// teria de ser tratado em todo o lado.
///
/// Cada aluno regista contra o **plano dele**. Numa aula de grupo o
/// circuito costuma ser igual para todos, mas neste estúdio o plano é
/// individual — e mostrar a prescrição de cada um é o que permite ao
/// instrutor dizer "hoje sobes para 60" com a informação à frente.
class GroupWorkoutScreen extends ConsumerStatefulWidget {
  const GroupWorkoutScreen({
    super.key,
    required this.occurrenceId,
    required this.title,
  });

  final String occurrenceId;

  /// O nome que fica no histórico de cada aluno ("Aula de Grupo ·
  /// qua, 19:00"). Copiado para a sessão, como em qualquer treino.
  final String title;

  @override
  ConsumerState<GroupWorkoutScreen> createState() => _GroupWorkoutScreenState();
}

class _GroupWorkoutScreenState extends ConsumerState<GroupWorkoutScreen> {
  String? _selectedMemberId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final bookingsAsync =
        ref.watch(occurrenceBookingsProvider(widget.occurrenceId));
    final membersById = <String, MemberSummary>{
      for (final m
          in ref.watch(membersProvider).valueOrNull ?? const <MemberSummary>[])
        m.uid: m,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Treino da turma'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _finishAll(membersById),
            child: const Text('Terminar todos'),
          ),
        ],
      ),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (bookings) {
          final attendees = bookings
              .where((b) => b.status == BookingStatus.booked)
              .map((b) => b.memberId)
              .toList();

          if (attendees.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Sem ninguém inscrito',
              message: 'Esta sessão ainda não tem inscritos. Assim que '
                  'houver, podes começar o treino de todos a partir daqui.',
            );
          }

          final selected = attendees.contains(_selectedMemberId)
              ? _selectedMemberId!
              : attendees.first;

          return Column(
            children: [
              _AttendeeStrip(
                attendees: attendees,
                membersById: membersById,
                selected: selected,
                onSelected: (memberId) =>
                    setState(() => _selectedMemberId = memberId),
              ),
              _StartAllBar(
                attendees: attendees,
                busy: _busy,
                onStartAll: () => _startAll(attendees, membersById),
              ),
              const Divider(height: 1),
              Expanded(
                child: _AthletePane(
                  key: ValueKey(selected),
                  memberId: selected,
                  member: membersById[selected],
                  sessionTitle: widget.title,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Abre uma sessão para quem ainda não tem nenhuma a decorrer.
  ///
  /// Quem já está a treinar (chegou mais cedo, ou o próprio começou
  /// pelo telemóvel) é deixado em paz — abrir uma segunda sessão
  /// significaria não saber a qual pertence a próxima série.
  Future<void> _startAll(
    List<String> attendees,
    Map<String, MemberSummary> membersById,
  ) async {
    // `await ... .future` e não `.valueOrNull`: um StreamProvider só é
    // inicializado quando alguém olha para ele, e este ecrã não o
    // observa em lado nenhum. Lido dentro do handler com `valueOrNull`,
    // a primeira leitura apanhava-o ainda em carregamento e o botão
    // não fazia nada — o mesmo engano já documentado em
    // `book_training_screen.dart`.
    final performedBy = (await ref.read(currentAppUserProvider.future))?.uid;
    if (performedBy == null) return;

    setState(() => _busy = true);
    var started = 0;
    try {
      final repository = ref.read(workoutSessionRepositoryProvider);
      for (final memberId in attendees) {
        final active =
            await ref.read(activeWorkoutSessionProvider(memberId).future);
        if (active != null) continue;
        await repository.startSession(
          memberId: memberId,
          workoutId: null,
          workoutName: widget.title,
          performedBy: performedBy,
        );
        started += 1;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(started == 0
              ? 'Já estavam todos a treinar.'
              : '$started treino(s) iniciado(s).'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível iniciar. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fecha as sessões da turma de uma vez.
  ///
  /// Uma sessão sem séries nenhumas é descartada em vez de guardada:
  /// no histórico de quem faltou a meio, um treino vazio é ruído.
  Future<void> _finishAll(Map<String, MemberSummary> membersById) async {
    final bookings =
        ref.read(occurrenceBookingsProvider(widget.occurrenceId)).valueOrNull ??
            const <Booking>[];
    final attendees = bookings
        .where((b) => b.status == BookingStatus.booked)
        .map((b) => b.memberId)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Terminar os treinos da turma?'),
        content: const Text(
          'Fecha os treinos a decorrer desta aula. Os que não tiverem '
          'nenhuma série registada são descartados.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    var finished = 0;
    var discarded = 0;
    try {
      final repository = ref.read(workoutSessionRepositoryProvider);
      for (final memberId in attendees) {
        final active =
            await ref.read(activeWorkoutSessionProvider(memberId).future);
        if (active == null) continue;
        if (active.sets.isEmpty) {
          await repository.discardSession(
            memberId: memberId,
            sessionId: active.id,
          );
          discarded += 1;
        } else {
          await repository.finishSession(
            memberId: memberId,
            sessionId: active.id,
          );
          finished += 1;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$finished treino(s) registado(s)'
            '${discarded > 0 ? ', $discarded sem séries descartado(s)' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível terminar. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A turma numa linha. É daqui que se salta de aluno para aluno — o
/// gesto que a versão individual não tinha e que torna isto usável
/// durante uma aula.
class _AttendeeStrip extends ConsumerWidget {
  const _AttendeeStrip({
    required this.attendees,
    required this.membersById,
    required this.selected,
    required this.onSelected,
  });

  final List<String> attendees;
  final Map<String, MemberSummary> membersById;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      // Altura fixa com folga para duas linhas de texto: a tira é
      // horizontal e tem de caber sem esmagar o nome.
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        itemCount: attendees.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final memberId = attendees[index];
          final name = membersById[memberId]?.name ?? memberId;
          final session =
              ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull;
          final isSelected = memberId == selected;

          return InkWell(
            onTap: () => onSelected(memberId),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 108,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.red.withValues(alpha: 0.16)
                    : AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.red : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    session == null
                        ? 'por iniciar'
                        : '${session.sets.length} série(s)',
                    style: TextStyle(
                      fontSize: 10,
                      color: session == null ? AppColors.mute : AppColors.ok,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StartAllBar extends ConsumerWidget {
  const _StartAllBar({
    required this.attendees,
    required this.busy,
    required this.onStartAll,
  });

  final List<String> attendees;
  final bool busy;
  final VoidCallback onStartAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = attendees
        .where((memberId) =>
            ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull ==
            null)
        .length;

    if (pending == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 15, color: AppColors.ok),
            SizedBox(width: 6),
            Text(
              'Toda a turma com treino a decorrer.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: busy ? null : onStartAll,
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 18),
          label: Text(
            pending == attendees.length
                ? 'Iniciar treino para a turma ($pending)'
                : 'Iniciar para os restantes ($pending)',
          ),
        ),
      ),
    );
  }
}

/// O painel do aluno selecionado: a sessão dele e o plano dele.
class _AthletePane extends ConsumerWidget {
  const _AthletePane({
    super.key,
    required this.memberId,
    required this.member,
    required this.sessionTitle,
  });

  final String memberId;
  final MemberSummary? member;
  final String sessionTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(activeWorkoutSessionProvider(memberId));
    final planAsync = ref.watch(trainingPlanProvider(memberId));
    final exercisesById = <String, Exercise>{
      for (final e
          in ref.watch(exercisesProvider).valueOrNull ?? const <Exercise>[])
        e.id: e,
    };

    final session = sessionAsync.valueOrNull;
    if (session == null) {
      return EmptyState(
        icon: Icons.play_circle_outline,
        title: '${member?.name ?? 'Este aluno'} ainda não começou',
        message: 'Usa "Iniciar treino para a turma" acima para abrir o '
            'treino de toda a gente de uma vez.',
      );
    }

    return planAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorState(error: error),
      data: (entries) {
        // A sessão de turma não aponta para um treino do plano
        // (`workoutId == null`), por isso mostram-se todos os
        // exercícios prescritos — é o instrutor que escolhe o que
        // fazer hoje, com a prescrição à frente.
        final planned = session.workoutId == null
            ? entries
            : entries.where((e) => e.workoutId == session.workoutId).toList();

        if (planned.isEmpty) {
          return EmptyState(
            icon: Icons.assignment_outlined,
            title: 'Sem plano de treino',
            message: '${member?.name ?? 'Este aluno'} ainda não tem '
                'exercícios prescritos, por isso não há o que registar. '
                'Monta-lhe o plano na ficha dele.',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _AthleteHeader(member: member, session: session),
            const SizedBox(height: 14),
            for (final entry in planned) ...[
              ExerciseLogger(
                key: ValueKey('${memberId}_${entry.id}'),
                memberId: memberId,
                sessionId: session.id,
                entry: entry,
                exercise: exercisesById[entry.exerciseId],
                done: session.setsFor(entry.exerciseId),
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _AthleteHeader extends StatelessWidget {
  const _AthleteHeader({required this.member, required this.session});

  final MemberSummary? member;
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Row(
        children: [
          Avatar(member?.name ?? '?'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member?.name ?? session.memberId,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.sets.length} série(s) · ${session.totalReps} reps',
                  style: const TextStyle(color: AppColors.mute, fontSize: 11),
                ),
              ],
            ),
          ),
          if (session.totalVolume > 0)
            Text(
              '${session.totalVolume.toStringAsFixed(0)} kg',
              style: AppTheme.display(fontSize: 16),
            ),
        ],
      ),
    );
  }
}
