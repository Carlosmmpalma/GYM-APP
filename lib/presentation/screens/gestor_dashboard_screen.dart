import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/session_occurrence.dart';
import '../widgets/today_classes.dart';

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
    // Contagens agregadas, não as listas: este é o primeiro ecrã que um
    // Gestor vê, e mostrar "412 ativos" lendo 412 documentos era pagar
    // a lista toda para desenhar um número. Ver
    // `MemberRepository.countActiveMembers`.
    final membersAsync = ref.watch(activeMemberCountProvider);
    final seriesAsync = ref.watch(activeSeriesCountProvider);
    // Esta continua a ser a lista: a lotação prevista precisa mesmo da
    // capacidade e das marcações de cada sessão, não de uma contagem.
    final occurrencesAsync = ref.watch(upcomingWeekOccurrencesProvider);

    // Fase 10 — sem `Scaffold`/`AppBar` próprios: passou a ser o corpo
    // do primeiro separador do Gestor (`HomeScreen`), que já os fornece.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // As aulas de hoje à cabeça, com o estado da chamada.
        //
        // Os quatro cartões de número abaixo olham todos para a FRENTE
        // — membros ativos, séries ativas, sessões dos próximos 7 dias,
        // lotação prevista. Nenhum respondia à pergunta que um gestor
        // faz ao fim do dia: "alguma chamada por fazer?". Para lá
        // chegar eram quatro toques, por Aulas/Horários → série →
        // ocorrência, e o estado só se via dentro de cada uma.
        //
        // Desaparece sozinha nos dias sem aulas, para não deixar um
        // título vazio no topo do painel.
        const TodayClasses(),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Membros ativos',
                failed: membersAsync.hasError,
                value: membersAsync.when(
                  loading: () => null,
                  error: (_, __) => null,
                  data: (count) => count.toString(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Séries ativas',
                failed: seriesAsync.hasError,
                value: seriesAsync.when(
                  loading: () => null,
                  error: (_, __) => null,
                  data: (count) => count.toString(),
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
                failed: occurrencesAsync.hasError,
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
                // "Ocupação média" dizia-se de sessões que ainda não
                // aconteceram, e lia-se como se fosse o enchimento real
                // do ginásio — uma aula de sexta ainda por encher punha
                // o número em 20% numa semana que acabou cheia. O
                // rótulo passou a dizer o que o número é: uma previsão.
                // A ocupação REALIZADA vive no painel de Retenção, e é
                // calculada só sobre sessões já dadas.
                label: 'Lotação prevista',
                failed: occurrencesAsync.hasError,
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
  const _StatCard({
    required this.label,
    required this.value,
    this.failed = false,
  });

  final String? value;
  final String label;

  /// A leitura falhou. Distinto de `value == null`, que é "ainda a
  /// carregar": um spinner eterno num cartão de números faz o Gestor
  /// esperar por algo que nunca vem.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (failed)
              const Tooltip(
                message: 'Não foi possível carregar este número.',
                child: Icon(Icons.cloud_off_outlined,
                    size: 26, color: AppColors.mute),
              )
            else
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
