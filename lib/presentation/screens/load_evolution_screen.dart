import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/load_history_entry.dart';
import '../widgets/design_system.dart';

final _dateFormat = DateFormat('d MMM yyyy', 'pt_PT');
final _shortDateFormat = DateFormat('d/M', 'pt_PT');

/// Um dia de treino deste exercício, resumido à série que conta.
///
/// **A melhor série do dia, e não todas.** Com o registo ao vivo (Fase
/// 11) cada exercício escreve um registo por série: quatro séries num
/// dia enchiam a evolução com quatro linhas iguais, e três treinos por
/// semana davam doze linhas por semana onde a pergunta é sempre a
/// mesma — "estou a subir?". A resposta a essa pergunta é a carga mais
/// alta do dia, com as repetições que saíram nela.
///
/// Empate na carga resolve-se pelas repetições: 60 kg × 10 é melhor
/// série do que 60 kg × 8, e é a que representa o dia.
class _TrainingDay {
  _TrainingDay({
    required this.day,
    required this.load,
    required this.reps,
    required this.sets,
  });

  final DateTime day;
  final double load;
  final int reps;

  /// Quantas séries com carga foram registadas nesse dia — o contexto
  /// que a linha perderia ao mostrar só a melhor.
  final int sets;
}

List<_TrainingDay> _byDay(List<LoadHistoryEntry> history) {
  final best = <DateTime, _TrainingDay>{};
  for (final entry in history) {
    final day = DateTime(
      entry.recordedAt.year,
      entry.recordedAt.month,
      entry.recordedAt.day,
    );
    final current = best[day];
    if (current == null) {
      best[day] =
          _TrainingDay(day: day, load: entry.load, reps: entry.reps, sets: 1);
      continue;
    }
    final isBetter = entry.load > current.load ||
        (entry.load == current.load && entry.reps > current.reps);
    best[day] = _TrainingDay(
      day: day,
      load: isBetter ? entry.load : current.load,
      reps: isBetter ? entry.reps : current.reps,
      sets: current.sets + 1,
    );
  }
  // Mais recente primeiro, como o resto dos históricos da app.
  return best.values.toList()..sort((a, b) => b.day.compareTo(a.day));
}

/// Fase 8 (UC16 atualizado) — "Evolução da carga": "cada atualização
/// fica registada, nunca sobrescreve a anterior".
///
/// Reescrito na Fase 11 depois de o registo ao vivo passar a escrever
/// um registo por série: a lista crua deixou de responder à pergunta
/// que traz aqui alguém. Agora é uma linha por DIA de treino — a
/// melhor série desse dia — com o gráfico por cima a mostrar a forma
/// da progressão, que é o que se lê num segundo.
class LoadEvolutionScreen extends ConsumerWidget {
  const LoadEvolutionScreen({
    super.key,
    required this.memberId,
    required this.exerciseId,
    required this.exerciseName,
  });

  final String memberId;
  final String exerciseId;
  final String exerciseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(
      loadHistoryProvider((memberId: memberId, exerciseId: exerciseId)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(exerciseName)),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (history) {
          if (history.isEmpty) {
            return const EmptyState(
              icon: Icons.show_chart,
              title: 'Ainda sem histórico',
              message: 'A carga deste exercício fica registada a cada série '
                  'feita, e a evolução aparece aqui a partir do primeiro '
                  'treino registado.',
            );
          }

          final days = _byDay(history);
          final current = days.first;
          final oldest = days.last;
          final delta = current.load - oldest.load;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PanelCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionLabel('Carga atual'),
                          const SizedBox(height: 4),
                          Text(
                            '${_kg(current.load)} kg × ${current.reps}',
                            style: AppTheme.display(fontSize: 24),
                          ),
                          Text(
                            _dateFormat.format(current.day),
                            style: const TextStyle(
                                color: AppColors.mute, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (days.length > 1)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${delta >= 0 ? '+' : ''}${_kg(delta)} kg',
                            style: AppTheme.display(
                              fontSize: 18,
                              color: delta >= 0 ? AppColors.ok : AppColors.warn,
                            ),
                          ),
                          Text(
                            'desde ${_shortDateFormat.format(oldest.day)}',
                            style: const TextStyle(
                                color: AppColors.mute, fontSize: 10),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (days.length > 1) ...[
                const SizedBox(height: 16),
                PanelCard(
                  child: SizedBox(
                    height: 120,
                    // Da esquerda (mais antigo) para a direita (hoje) —
                    // ao contrário da lista, porque um gráfico que
                    // desce no tempo lê-se ao contrário do que o olho
                    // espera.
                    child: _LoadChart(days: days.reversed.toList()),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const SectionLabel('Por dia de treino'),
              const SizedBox(height: 8),
              for (var i = 0; i < days.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DayRow(
                    day: days[i],
                    // Comparado com o treino ANTERIOR (o seguinte na
                    // lista, que está ordenada do mais recente para o
                    // mais antigo).
                    previous: i + 1 < days.length ? days[i + 1] : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _kg(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.previous});

  final _TrainingDay day;
  final _TrainingDay? previous;

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : day.load - previous!.load;

    return PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dateFormat.format(day.day),
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  day.sets == 1
                      ? '1 série registada'
                      : '${day.sets} séries registadas',
                  style: const TextStyle(color: AppColors.mute, fontSize: 11),
                ),
              ],
            ),
          ),
          if (delta != null && delta != 0) ...[
            Text(
              '${delta > 0 ? '+' : ''}${_kg(delta)}',
              style: TextStyle(
                fontSize: 11,
                color: delta > 0 ? AppColors.ok : AppColors.warn,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '${_kg(day.load)} kg × ${day.reps}',
            style: AppTheme.display(fontSize: 15, color: AppColors.red),
          ),
        ],
      ),
    );
  }
}

/// Gráfico de linha, desenhado à mão.
///
/// Sem biblioteca de charts: uma dependência nova para uma linha e
/// alguns pontos não se paga, e um pacote de gráficos traz consigo
/// temas próprios que teriam de ser dobrados ao design da app.
class _LoadChart extends StatelessWidget {
  const _LoadChart({required this.days});

  final List<_TrainingDay> days;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LoadChartPainter(days),
      size: Size.infinite,
    );
  }
}

class _LoadChartPainter extends CustomPainter {
  _LoadChartPainter(this.days);

  final List<_TrainingDay> days;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.length < 2) return;

    final loads = days.map((d) => d.load).toList();
    final maxLoad = loads.reduce((a, b) => a > b ? a : b);
    final minLoad = loads.reduce((a, b) => a < b ? a : b);
    // Escala com margem em cima e em baixo; o caso de carga constante
    // desenharia uma divisão por zero, e é resolvido com uma linha ao
    // meio (que é a leitura correta: não mudou).
    final range = maxLoad - minLoad;
    const padding = 16.0;
    final usableHeight = size.height - padding * 2;

    double yFor(double load) {
      if (range == 0) return size.height / 2;
      return padding + (1 - (load - minLoad) / range) * usableHeight;
    }

    final step = size.width / (days.length - 1);
    final points = [
      for (var i = 0; i < days.length; i++)
        Offset(i * step, yFor(days[i].load)),
    ];

    // Área sob a linha, muito ténue: dá volume ao gráfico sem competir
    // com a linha.
    final area = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      area.lineTo(point.dx, point.dy);
    }
    area.lineTo(points.last.dx, size.height);
    area.close();
    canvas.drawPath(
      area,
      Paint()..color = AppColors.red.withValues(alpha: 0.10),
    );

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.red
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    for (final point in points) {
      canvas.drawCircle(point, 3, Paint()..color = AppColors.red);
    }
  }

  @override
  bool shouldRepaint(covariant _LoadChartPainter oldDelegate) =>
      oldDelegate.days != days;
}
