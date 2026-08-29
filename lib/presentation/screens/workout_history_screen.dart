import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/workout_session.dart';
import '../widgets/design_system.dart';
import '../widgets/catalogue_delete.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/utils/firebase_error_text.dart';

final _dateFormat = DateFormat("d 'de' MMMM", 'pt_PT');
final _timeFormat = DateFormat('HH:mm', 'pt_PT');
final _monthFormat = DateFormat('MMMM yyyy', 'pt_PT');

/// Fase 11 — o histórico de treinos feitos.
///
/// Responde à pergunta que um aluno e um instrutor fazem de formas
/// diferentes mas sobre a mesma coisa: "o que é que eu fiz?" e "o que é
/// que ele tem feito?". Daí ser o mesmo ecrã para os dois — muda só por
/// onde se lá chega.
///
/// **Agrupado por mês e filtrável por treino.** Três idas ao ginásio
/// por semana são ~150 sessões por ano: uma lista corrida delas é uma
/// parede de cartões onde não se encontra nada. O mês dá a régua com
/// que qualquer pessoa pensa em treino ("em julho fui doze vezes"), e o
/// filtro por treino responde à outra pergunta frequente — "quando foi
/// a última vez que fiz pernas?".
class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({
    super.key,
    required this.memberId,
    this.title = 'Treinos feitos',
  });

  final String memberId;
  final String title;

  @override
  ConsumerState<WorkoutHistoryScreen> createState() =>
      _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  /// Nome do treino escolhido; `null` = todos. Filtra-se pelo NOME e
  /// não pelo `workoutId` porque é o nome que está no registo (o treino
  /// pode ter sido apagado do plano entretanto) e é por ele que a
  /// pessoa procura.
  String? _workoutName;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(workoutSessionsProvider(widget.memberId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Ainda sem treinos registados',
              message: 'Assim que um treino for feito e registado, fica aqui '
                  'o que se fez em cada série — e é isso que permite ver a '
                  'evolução ao longo do tempo.',
            );
          }

          // Uma sessão em curso não é histórico — aparece no topo, mas
          // marcada, para não se confundir com um treino terminado.
          final finished = sessions.where((s) => !s.isActive).toList();

          // Resolvido UMA vez para o histórico todo, e não por cartão:
          // um pedido por sessão seria trocar uma leitura grande por
          // dez pequenas. E só os exercícios que aparecem aqui — a
          // biblioteca inteira era o que se lia antes.
          final exercisesById = ref
                  .watch(exercisesByIdsProvider(exerciseKeyFor(
                    sessions.expand((s) => s.sets.map((set) => set.exerciseId)),
                  )))
                  .valueOrNull ??
              const <String, Exercise>{};

          final counts = <String, int>{};
          for (final session in sessions) {
            counts[session.workoutName] =
                (counts[session.workoutName] ?? 0) + 1;
          }
          final options = counts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final visible = _workoutName == null
              ? sessions
              : sessions.where((s) => s.workoutName == _workoutName).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HistorySummary(sessions: visible),
              // Um treino só no histórico não tem nada para filtrar.
              if (options.length > 1) ...[
                const SizedBox(height: 12),
                FilterChipsRow<String>(
                  options: [
                    for (final entry in options)
                      (entry.key, entry.key, entry.value)
                  ],
                  selected: _workoutName,
                  onSelected: (value) => setState(() => _workoutName = value),
                  allCount: sessions.length,
                ),
              ],
              const SizedBox(height: 16),
              if (visible.isEmpty)
                const PanelCard(
                  child: Text(
                    'Nenhum treino deste tipo no histórico.',
                    style: TextStyle(color: AppColors.mute, fontSize: 12),
                  ),
                ),
              for (final group in _byMonth(visible)) ...[
                SectionLabel(_monthFormat.format(group.month)),
                const SizedBox(height: 8),
                for (final session in group.sessions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SessionCard(
                      key: ValueKey(session.id),
                      memberId: widget.memberId,
                      session: session,
                      isLatestFinished: finished.isNotEmpty &&
                          finished.first.id == session.id,
                      exercisesById: exercisesById,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Sessões de um mês, do mais recente para o mais antigo.
class _MonthGroup {
  _MonthGroup(this.month, this.sessions);

  final DateTime month;
  final List<WorkoutSession> sessions;
}

List<_MonthGroup> _byMonth(List<WorkoutSession> sessions) {
  final groups = <DateTime, List<WorkoutSession>>{};
  for (final session in sessions) {
    final month = DateTime(session.startedAt.year, session.startedAt.month);
    groups.putIfAbsent(month, () => []).add(session);
  }
  final months = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final month in months) _MonthGroup(month, groups[month]!)];
}

/// O que se lê num relance antes de descer pela lista: quantos treinos,
/// quanto volume, e há quanto tempo foi o último.
class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.sessions});

  final List<WorkoutSession> sessions;

  @override
  Widget build(BuildContext context) {
    final finished = sessions.where((s) => !s.isActive).toList();
    final volume = finished.fold<double>(0, (sum, s) => sum + s.totalVolume);
    final last = finished.isNotEmpty ? finished.first.startedAt : null;
    final daysSince =
        last == null ? null : DateTime.now().difference(last).inDays;

    return PanelCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${finished.length}',
                    style: AppTheme.display(fontSize: 22)),
                const Text('treinos',
                    style: TextStyle(color: AppColors.mute, fontSize: 10)),
              ],
            ),
          ),
          if (volume > 0)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${(volume / 1000).toStringAsFixed(1)} t',
                      style: AppTheme.display(fontSize: 22)),
                  const Text('volume total',
                      style: TextStyle(color: AppColors.mute, fontSize: 10)),
                ],
              ),
            ),
          if (daysSince != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    daysSince == 0 ? 'hoje' : '$daysSince d',
                    style: AppTheme.display(fontSize: 22),
                  ),
                  const Text('desde o último',
                      style: TextStyle(color: AppColors.mute, fontSize: 10)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({
    super.key,
    required this.memberId,
    required this.session,
    required this.isLatestFinished,
    required this.exercisesById,
  });

  final String memberId;
  final WorkoutSession session;
  final bool isLatestFinished;

  /// Resolvido pelo ecrã para o histórico todo — ver a nota lá.
  final Map<String, Exercise> exercisesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final canManage =
        (appUser?.isManager ?? false) || (appUser?.isInstructor ?? false);

    final duration = session.duration;
    final summary = [
      '${session.sets.length} série(s)',
      if (session.totalVolume > 0)
        '${session.totalVolume.toStringAsFixed(0)} kg de volume',
      if (duration != null) '${duration.inMinutes} min',
    ].join(' · ');

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.workoutName.toUpperCase(),
                  style: AppTheme.display(fontSize: 14),
                ),
              ),
              if (session.isActive)
                const Pill('Em curso', tone: PillTone.warn)
              else if (isLatestFinished)
                const Pill('Mais recente', tone: PillTone.ok),
              // Só o estúdio elimina treinos: são a base das
              // estatísticas do aluno, e um aluno a apagar os treinos
              // maus falseava a própria evolução sem dar por isso.
              if (canManage)
                IconButton(
                  tooltip: 'Eliminar treino',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _delete(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_dateFormat.format(session.startedAt)} às '
            '${_timeFormat.format(session.startedAt)}',
            style: const TextStyle(color: AppColors.mute, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(summary, style: const TextStyle(fontSize: 12)),
          if (session.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              session.notes,
              style: const TextStyle(
                  color: AppColors.mute, fontSize: 11, height: 1.4),
            ),
          ],
          if (session.sets.isNotEmpty) ...[
            const Divider(height: 20),
            // Agrupado por exercício, e não pela ordem cronológica das
            // séries: quem lê um treino passado quer ver "supino: 3
            // séries", não a sequência intercalada em que aconteceram.
            for (final exerciseId in _exerciseOrder()) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        exercisesById[exerciseId]?.name ?? exerciseId,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        session
                            .setsFor(exerciseId)
                            .map((s) => s.load != null
                                ? '${s.load!.toStringAsFixed(0)}×${s.reps}'
                                : '${s.reps}')
                            .join('  ·  '),
                        style: const TextStyle(
                            color: AppColors.mute, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Ordem de aparecimento na sessão — a ordem em que os exercícios
  /// foram efetivamente feitos.
  List<String> _exerciseOrder() {
    final seen = <String>[];
    for (final set in session.sets) {
      if (!seen.contains(set.exerciseId)) seen.add(set.exerciseId);
    }
    return seen;
  }

  /// Um treino registado por engano não fica só no histórico: entra na
  /// frequência semanal, na evolução de carga e no 1RM estimado, e
  /// distorce-os para sempre. As cargas registadas nesta sessão vão com
  /// ela.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Eliminar este treino?',
      consequence: '${session.sets.length} série(s) registadas '
          'desaparecem, e com elas as cargas que este treino acrescentou '
          'ao histórico. As estatísticas do aluno passam a contar sem '
          'ele.',
      confirmLabel: 'Eliminar treino',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(workoutSessionRepositoryProvider).deleteSession(
            memberId: memberId,
            sessionId: session.id,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treino eliminado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível eliminar. Tenta outra vez.')),
        ),
      );
    }
  }
}
