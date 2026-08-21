import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/session_series.dart';
import '../widgets/design_system.dart';
import 'create_series_screen.dart';
import 'occurrence_detail_screen.dart';
import 'series_detail_screen.dart';

const _weekdayNames = {
  DateTime.monday: 'Segunda',
  DateTime.tuesday: 'Terça',
  DateTime.wednesday: 'Quarta',
  DateTime.thursday: 'Quinta',
  DateTime.friday: 'Sexta',
  DateTime.saturday: 'Sábado',
  DateTime.sunday: 'Domingo',
};

/// Fase 5 (guia-desenvolvimento.md) — "Ecrã Gestor: aulas/PT
/// recorrentes". Lista as [SessionSeries] do tenant; FAB "+" abre
/// [CreateSeriesScreen] (série semanal OU ocorrência "só esta data" —
/// UC17/UC19 atualizado). Cada série abre [SeriesDetailScreen]
/// ("ajustar uma semana da série").
///
/// Só Gestor gere isto por agora (decisão explícita, ver
/// `app/README.md` Fase 5) — uma área própria para o Instrutor fica
/// para a Fase 6 do guia ("Operações do dia a dia").
class ManageSeriesScreen extends ConsumerWidget {
  const ManageSeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(seriesProvider);
    final occurrencesAsync = ref.watch(allUpcomingOccurrencesProvider);
    final servicesAsync = ref.watch(servicesProvider);
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Aulas / Horários')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateSeriesScreen()),
        ),
        tooltip: 'Nova série ou sessão',
        child: const Icon(Icons.add),
      ),
      body: seriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (seriesList) {
          final servicesById = {
            for (final s in servicesAsync.valueOrNull ?? const []) s.id: s,
          };
          final staffByUid = {
            for (final s in staffAsync.valueOrNull ?? const []) s.uid: s,
          };
          // Fase 6 — ocorrências "só esta data" (seriesId == null):
          // até aqui, uma vez criadas, nunca mais apareciam em lado
          // nenhum da Gestão. Filtrado client-side sobre a mesma
          // stream já usada em `BookTrainingScreen` (Fase 5) — sem
          // query nova.
          final adHocOccurrences = (occurrencesAsync.valueOrNull ?? const [])
              .where((o) => o.seriesId == null)
              .toList();

          if (seriesList.isEmpty && adHocOccurrences.isEmpty) {
            return EmptyState(
              icon: Icons.event_note_outlined,
              title: 'Horário vazio',
              message: 'Aqui defines as aulas: uma série repete-se todas '
                  'as semanas no mesmo dia e hora, uma sessão avulsa '
                  'acontece só numa data. É isto que os alunos veem em '
                  '"Marcar treino".',
              prerequisite: servicesById.isEmpty
                  ? 'Cria primeiro os serviços (Gestão › Serviços): cada '
                      'aula tem de ser de um serviço.'
                  : null,
              actionLabel: 'Criar a primeira aula',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateSeriesScreen()),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (seriesList.isNotEmpty) ...[
                Text('Séries', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final series in seriesList) ...[
                  _SeriesTile(
                    series: series,
                    serviceName: servicesById[series.serviceId]?.name ??
                        series.serviceId,
                    instructorName: series.instructorId == null
                        ? null
                        : staffByUid[series.instructorId]?.name,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              if (adHocOccurrences.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Sessões avulsas',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final occurrence in adHocOccurrences) ...[
                  Card(
                    child: ListTile(
                      title: Text(
                        servicesById[occurrence.serviceId]?.name ??
                            occurrence.serviceId,
                      ),
                      subtitle: Text(
                        '${seriesDateFormat.format(occurrence.startAt)} · '
                        '${occurrence.activeBookingCount}/${occurrence.capacity} inscritos',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OccurrenceDetailScreen(
                              occurrenceId: occurrence.id),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SeriesTile extends StatelessWidget {
  const _SeriesTile({
    required this.series,
    required this.serviceName,
    required this.instructorName,
  });

  final SessionSeries series;
  final String serviceName;
  final String? instructorName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(serviceName),
        subtitle: Text(
          '${_weekdayNames[series.dayOfWeek] ?? series.dayOfWeek} · '
          '${series.startTime} · ${series.capacityLabel}'
          '${instructorName != null ? ' · $instructorName' : ''}'
          '${series.isActive ? '' : ' · cancelada'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)),
        ),
      ),
    );
  }
}

/// Formato curto de data usado pelos ecrãs de séries/ocorrências.
final seriesDateFormat = DateFormat('EEE, d MMM · HH:mm', 'pt_PT');

String weekdayName(int dayOfWeek) => _weekdayNames[dayOfWeek] ?? '$dayOfWeek';
