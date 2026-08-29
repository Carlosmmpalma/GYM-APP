import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/member_stats.dart';
import '../../domain/entities/member_summary.dart';
import '../widgets/design_system.dart';
import 'assessment_list_screen.dart';
import 'load_evolution_screen.dart';
import 'workout_history_screen.dart';
import '../../domain/entities/workout_session.dart';

final _dayFormat = DateFormat('d MMM yyyy', 'pt_PT');
final _shortDayFormat = DateFormat('d/M', 'pt_PT');

/// Estatísticas de um aluno, para quem o acompanha.
///
/// O Instrutor tinha o histórico (treino a treino) e as avaliações
/// (uma a uma), mas nenhum sítio onde ver a pessoa toda: se está a
/// aparecer, se está a subir, se treina sempre a mesma coisa. Isso é o
/// que se olha antes de uma conversa com o aluno, e era precisamente o
/// que faltava.
///
/// As métricas são as que as apps da área mostram (Hevy, Strong,
/// Trainerize, TrueCoach), pela ordem em que elas as põem — e a ordem
/// é a parte importante: a consistência primeiro, porque é o que se
/// traduz numa ação hoje; a força a seguir, porque é o que motiva; a
/// composição corporal por último, porque é a que mexe mais devagar e
/// a que mais gente lê mal. Ver `MemberStats` para o porquê de cada
/// número.
///
/// Tudo sai de duas queries que a ficha do aluno já fazia (sessões de
/// treino e avaliações) mais a biblioteca de exercícios, que está em
/// memória: o ecrã não custa uma leitura a mais.
class MemberStatsScreen extends ConsumerWidget {
  const MemberStatsScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(workoutSessionsProvider(member.uid));
    // Só os exercícios que aparecem nos treinos deste aluno. Ver a nota
    // em `ExerciseRepository.getExercisesByIds`.
    final exercisesAsync = ref.watch(
      exercisesByIdsProvider(
        exerciseKeyFor(
          (sessionsAsync.valueOrNull ?? const <WorkoutSession>[])
              .expand((s) => s.sets.map((set) => set.exerciseId)),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estatísticas'),
        actions: [
          IconButton(
            tooltip: 'Histórico de treinos',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkoutHistoryScreen(
                  memberId: member.uid,
                  title: 'Treinos — ${member.name}',
                ),
              ),
            ),
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (sessions) {
          final exercisesById =
              exercisesAsync.valueOrNull ?? const <String, Exercise>{};
          final stats = computeMemberStats(
            sessions: sessions,
            exercisesById: exercisesById,
            now: DateTime.now(),
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!stats.hasData)
                const EmptyState(
                  icon: Icons.insights_outlined,
                  title: 'Ainda sem treinos registados',
                  message: 'As estatísticas saem do que fica registado em '
                      'cada treino — séries, cargas e repetições. Assim que '
                      'houver treinos registados (pelo aluno ou por ti, ao '
                      'lado dele), aparece aqui a evolução.',
                )
              else ...[
                _SummaryRow(stats: stats),
                const SizedBox(height: 24),
                const SectionLabel('Consistência'),
                const SizedBox(height: 2),
                const Text(
                  'Treinos por semana. É o número que melhor diz se alguém '
                  'vai continuar sócio daqui a seis meses.',
                  style: TextStyle(
                      color: AppColors.mute, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 10),
                PanelCard(child: _ConsistencyChart(weeks: stats.weeks)),
                const SizedBox(height: 24),
                const SectionLabel('Equilíbrio'),
                const SizedBox(height: 2),
                Text(
                  'Séries por grupo muscular nos últimos ${stats.windowDays} '
                  'dias.',
                  style: const TextStyle(
                      color: AppColors.mute, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 10),
                _MuscleBalance(setsByGroup: stats.setsByMuscleGroup),
                const SizedBox(height: 24),
                const SectionLabel('Força'),
                const SizedBox(height: 2),
                const Text(
                  'A melhor série de cada exercício e a estimativa de 1RM '
                  '(fórmula de Epley, só até 12 repetições).',
                  style: TextStyle(
                      color: AppColors.mute, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 10),
                for (final exercise in stats.strengthByExercise.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _StrengthRow(member: member, strength: exercise),
                  ),
              ],
              const SizedBox(height: 24),
              const SectionLabel('Composição corporal'),
              const SizedBox(height: 10),
              _AssessmentsSection(member: member),
            ],
          );
        },
      ),
    );
  }
}

/// Os quatro números do topo. Um deles — "há quanto tempo não treina" —
/// é o único que se traduz numa ação imediata, e por isso muda de cor.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});

  final MemberStats stats;

  @override
  Widget build(BuildContext context) {
    final days = stats.daysSinceLastSession;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: '${stats.sessionsInWindow}',
                label: 'treinos\n(${stats.windowDays} dias)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                value: '${stats.weekStreak}',
                label: stats.weekStreak == 1
                    ? 'semana\nseguida'
                    : 'semanas\nseguidas',
                valueColor: stats.weekStreak >= 2 ? AppColors.ok : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: stats.volumeInWindow >= 1000
                    ? '${(stats.volumeInWindow / 1000).toStringAsFixed(1)} t'
                    : '${stats.volumeInWindow.toStringAsFixed(0)} kg',
                label: 'volume\n(${stats.windowDays} dias)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                value: days == null
                    ? '—'
                    : days == 0
                        ? 'hoje'
                        : '$days d',
                label: 'desde o\núltimo treino',
                // Duas semanas sem aparecer é o sinal a que vale a pena
                // reagir — é a mesma régua do painel de retenção.
                valueColor: days != null && days >= 14 ? AppColors.warn : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.display(
              fontSize: 22,
              color: valueColor ?? AppColors.bone,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                color: AppColors.mute, fontSize: 10, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Barras por semana. Widgets simples em vez de um `CustomPainter`:
/// são doze barras, e assim o leitor de ecrã ainda as consegue
/// anunciar.
class _ConsistencyChart extends StatelessWidget {
  const _ConsistencyChart({required this.weeks});

  final List<TrainingWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final max = weeks.fold<int>(1, (m, w) => w.sessions > m ? w.sessions : m);

    return Column(
      children: [
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final week in weeks)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Semantics(
                      label:
                          'Semana de ${_shortDayFormat.format(week.monday)}: '
                          '${week.sessions} treino(s)',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            week.sessions == 0 ? '' : '${week.sessions}',
                            style: const TextStyle(
                                color: AppColors.mute, fontSize: 9),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: 8 + (week.sessions / max) * 62,
                            decoration: BoxDecoration(
                              color: week.sessions == 0
                                  ? AppColors.mute.withValues(alpha: 0.18)
                                  : AppColors.red,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _shortDayFormat.format(weeks.first.monday),
              style: const TextStyle(color: AppColors.dim, fontSize: 10),
            ),
            const Text(
              'esta semana',
              style: TextStyle(color: AppColors.dim, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

class _MuscleBalance extends StatelessWidget {
  const _MuscleBalance({required this.setsByGroup});

  final Map<String, int> setsByGroup;

  @override
  Widget build(BuildContext context) {
    if (setsByGroup.isEmpty) {
      return const PanelCard(
        child: Text(
          'Sem séries registadas neste período.',
          style: TextStyle(color: AppColors.mute, fontSize: 12),
        ),
      );
    }

    final entries = setsByGroup.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return PanelCard(
      child: Column(
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: entry.value / total,
                        minHeight: 8,
                        backgroundColor: AppColors.mute.withValues(alpha: 0.18),
                        valueColor: const AlwaysStoppedAnimation(AppColors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${entry.value} série${entry.value == 1 ? '' : 's'}',
                      textAlign: TextAlign.right,
                      style:
                          const TextStyle(color: AppColors.mute, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StrengthRow extends StatelessWidget {
  const _StrengthRow({required this.member, required this.strength});

  final MemberSummary member;
  final ExerciseStrength strength;

  @override
  Widget build(BuildContext context) {
    final progress = strength.progressPercent;

    return PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      // O detalhe já existe: a evolução da carga, dia a dia.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoadEvolutionScreen(
            memberId: member.uid,
            exerciseId: strength.exerciseId,
            exerciseName: strength.name,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strength.name, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${strength.sessions} treino${strength.sessions == 1 ? '' : 's'} · '
                  '${strength.totalSets} série${strength.totalSets == 1 ? '' : 's'} · '
                  'melhor ${_kg(strength.bestLoad)} × ${strength.bestLoadReps}',
                  style: const TextStyle(color: AppColors.mute, fontSize: 11),
                ),
              ],
            ),
          ),
          if (progress != null && progress.abs() >= 1) ...[
            Text(
              '${progress > 0 ? '+' : ''}${progress.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: progress > 0 ? AppColors.ok : AppColors.warn,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                strength.estimatedOneRm == null
                    ? '—'
                    : _kg(strength.estimatedOneRm!),
                style: AppTheme.display(fontSize: 15, color: AppColors.red),
              ),
              const Text(
                '1RM est.',
                style: TextStyle(color: AppColors.dim, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Peso, massa gorda e massa muscular: o essencial de uma avaliação,
/// com a variação desde a primeira. As restantes medidas ficam na
/// avaliação em si — aqui interessa a direção, não a ficha toda.
class _AssessmentsSection extends ConsumerWidget {
  const _AssessmentsSection({required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessmentsAsync = ref.watch(assessmentsProvider(member.uid));

    return assessmentsAsync.when(
      loading: () => const PanelCard(
        child: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      // Sem consentimento para dados de saúde, o servidor recusa a
      // leitura — e isso não é um erro a mostrar em vermelho.
      error: (error, stack) => const PanelCard(
        child: Text(
          'Sem acesso às avaliações deste aluno.',
          style: TextStyle(color: AppColors.mute, fontSize: 12),
        ),
      ),
      data: (assessments) {
        if (assessments.isEmpty) {
          return PanelCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AssessmentListScreen(member: member),
              ),
            ),
            child: const Text(
              'Ainda não há avaliações físicas. Toca para fazer a primeira.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          );
        }

        // A lista chega da mais recente para a mais antiga.
        final current = assessments.first;
        final first = assessments.last;

        return PanelCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AssessmentListScreen(member: member),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MeasureRow(
                label: 'Peso',
                value: '${current.peso.toStringAsFixed(1)} kg',
                delta:
                    assessments.length > 1 ? current.peso - first.peso : null,
                unit: 'kg',
              ),
              _MeasureRow(
                label: 'Massa gorda',
                value: '${current.percentMassaGorda.toStringAsFixed(1)} %',
                delta: assessments.length > 1
                    ? current.percentMassaGorda - first.percentMassaGorda
                    : null,
                unit: 'pp',
              ),
              _MeasureRow(
                label: 'Massa muscular',
                value: '${current.massaMuscular.toStringAsFixed(1)} kg',
                delta: assessments.length > 1
                    ? current.massaMuscular - first.massaMuscular
                    : null,
                unit: 'kg',
              ),
              _MeasureRow(
                label: 'IMC',
                value: current.imc.toStringAsFixed(1),
                delta: assessments.length > 1 ? current.imc - first.imc : null,
                unit: '',
              ),
              const SizedBox(height: 4),
              Text(
                assessments.length > 1
                    ? '${assessments.length} avaliações · variação desde '
                        '${_dayFormat.format(first.createdAt)}'
                    : 'Primeira avaliação em '
                        '${_dayFormat.format(current.createdAt)}',
                style: const TextStyle(color: AppColors.dim, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MeasureRow extends StatelessWidget {
  const _MeasureRow({
    required this.label,
    required this.value,
    required this.delta,
    required this.unit,
  });

  final String label;
  final String value;
  final double? delta;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          // Sem cor de "bom" ou "mau": ganhar peso é o objetivo de
          // quem treina para massa e o contrário de quem treina para
          // emagrecer. A app mostra a direção; quem interpreta é o
          // instrutor.
          if (delta != null && delta!.abs() >= 0.1)
            Text(
              '${delta! > 0 ? '+' : ''}${delta!.toStringAsFixed(1)}'
              '${unit.isEmpty ? '' : ' $unit'}',
              style: const TextStyle(color: AppColors.mute, fontSize: 11),
            ),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

String _kg(double value) => value == value.roundToDouble()
    ? '${value.toStringAsFixed(0)} kg'
    : '${value.toStringAsFixed(1)} kg';
