import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/session_occurrence.dart';

/// UC25 — "Visão global": resumo do estado do ginásio para o Gestor,
/// sem ter de entrar em cada ecrã de gestão individualmente. Versão
/// mínima, deliberadamente sem "aulas/horários de todas as
/// modalidades" tal como o mockup mostra — `Modality` não existe ainda
/// em nenhuma parte da app (Domain Model v1 §8-9, sinalizado no guia
/// para uma fase futura); os números abaixo agregam TODAS as
/// ocorrências independentemente de serviço, o que já é o essencial da
/// pergunta "como está o ginásio esta semana" sem precisar dessa peça.
class GestorDashboardScreen extends ConsumerWidget {
  const GestorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);
    final seriesAsync = ref.watch(seriesProvider);
    final occurrencesAsync = ref.watch(upcomingWeekOccurrencesProvider);

    // Fase 10 — sem `Scaffold`/`AppBar` próprios: passou a ser o corpo
    // do primeiro separador do Gestor (`HomeScreen`), que já os fornece.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Membros ativos',
                value: membersAsync.when(
                  loading: () => null,
                  error: (_, __) => null,
                  data: (members) =>
                      members.where((m) => m.active).length.toString(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Séries ativas',
                value: seriesAsync.when(
                  loading: () => null,
                  error: (_, __) => null,
                  data: (series) =>
                      series.where((s) => s.isActive).length.toString(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Sessões (próx. 7 dias)',
                value: occurrencesAsync.when(
                  loading: () => null,
                  error: (_, __) => null,
                  data: (occurrences) => occurrences
                      .where(
                          (o) => o.status == SessionOccurrenceStatus.scheduled)
                      .length
                      .toString(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Ocupação média',
                value: occurrencesAsync.when(
                  loading: () => null,
                  error: (_, __) => null,
                  data: _averageOccupancyLabel,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _averageOccupancyLabel(List<SessionOccurrence> occurrences) {
    final scheduled = occurrences
        .where((o) =>
            o.status == SessionOccurrenceStatus.scheduled && o.capacity > 0)
        .toList();
    if (scheduled.isEmpty) return '—';
    final avg = scheduled
            .map((o) => o.activeBookingCount / o.capacity)
            .reduce((a, b) => a + b) /
        scheduled.length;
    return '${(avg * 100).round()}%';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            value == null
                ? const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(value!,
                    style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
