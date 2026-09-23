import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/utils/search_text.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/session_series.dart';
import '../../domain/entities/staff_summary.dart';
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
///
/// Fase 11 (auditoria) — ganhou procura e filtro por serviço, e passou
/// a ordenar as séries por dia da semana e hora. A lista chegava pela
/// ordem em que o Firestore devolvia os documentos, o que para um
/// gestor é ordem nenhuma; e as séries canceladas ficavam misturadas
/// com as ativas, separadas só por um "· cancelada" no fim de uma
/// linha de texto cinzento.
class ManageSeriesScreen extends ConsumerStatefulWidget {
  const ManageSeriesScreen({super.key});

  @override
  ConsumerState<ManageSeriesScreen> createState() => _ManageSeriesScreenState();
}

class _ManageSeriesScreenState extends ConsumerState<ManageSeriesScreen> {
  String _query = '';
  String? _serviceId;

  @override
  Widget build(BuildContext context) {
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
          final servicesById = <String, Service>{
            for (final s in servicesAsync.valueOrNull ?? const <Service>[])
              s.id: s,
          };
          final staffByUid = <String, StaffSummary>{
            for (final s in staffAsync.valueOrNull ?? const <StaffSummary>[])
              s.uid: s,
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
                  'acontece só numa data. É isto que os alunos veem no '
                  'separador "Aulas".',
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

          // Ordenadas como o horário é lido: por dia da semana e,
          // dentro do dia, por hora.
          final sorted = [...seriesList]..sort((a, b) {
              final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
              return byDay != 0 ? byDay : a.startTime.compareTo(b.startTime);
            });

          String nameOf(String serviceId) =>
              servicesById[serviceId]?.name ?? serviceId;
          String? instructorOf(String? uid) =>
              uid == null ? null : staffByUid[uid]?.name;

          bool matchesFilters(String serviceId, String? instructorName,
              [String extra = '']) {
            if (_serviceId != null && serviceId != _serviceId) return false;
            return searchMatchesAny(
              [nameOf(serviceId), instructorName ?? '', extra],
              _query,
            );
          }

          final visibleSeries = sorted
              .where((s) => matchesFilters(s.serviceId,
                  instructorOf(s.instructorId), weekdayName(s.dayOfWeek)))
              .toList();
          final activeSeries = visibleSeries.where((s) => s.isActive).toList();
          final cancelledSeries =
              visibleSeries.where((s) => !s.isActive).toList();
          final visibleAdHoc = adHocOccurrences
              .where((o) =>
                  matchesFilters(o.serviceId, instructorOf(o.instructorId)))
              .toList();

          // Contagens por serviço para os chips — só serviços que
          // TÊM horário, para não oferecer um filtro que abre vazio.
          final counts = <String, int>{};
          for (final series in sorted) {
            counts[series.serviceId] = (counts[series.serviceId] ?? 0) + 1;
          }
          for (final occurrence in adHocOccurrences) {
            counts[occurrence.serviceId] =
                (counts[occurrence.serviceId] ?? 0) + 1;
          }
          final serviceOptions = counts.entries
              .map((e) => (e.key, nameOf(e.key), e.value))
              .toList()
            ..sort((a, b) => a.$2.compareTo(b.$2));

          final nothingVisible = activeSeries.isEmpty &&
              cancelledSeries.isEmpty &&
              visibleAdHoc.isEmpty;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SearchField(
                  hintText: 'Procurar por serviço, instrutor ou dia',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (serviceOptions.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: FilterChipsRow<String>(
                    options: serviceOptions,
                    selected: _serviceId,
                    onSelected: (value) => setState(() => _serviceId = value),
                    allCount: counts.values.fold<int>(0, (a, b) => a + b),
                  ),
                ),
              Expanded(
                child: nothingVisible
                    ? const EmptyState(
                        icon: Icons.search_off_outlined,
                        title: 'Nada encontrado',
                        message: 'Nenhuma aula corresponde à procura. '
                            'Experimenta outro serviço, instrutor ou dia da '
                            'semana.',
                      )
                    : _buildList(
                        context,
                        activeSeries: activeSeries,
                        cancelledSeries: cancelledSeries,
                        adHocOccurrences: visibleAdHoc,
                        servicesById: servicesById,
                        staffByUid: staffByUid,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required List<SessionSeries> activeSeries,
    required List<SessionSeries> cancelledSeries,
    required List<SessionOccurrence> adHocOccurrences,
    required Map<String, Service> servicesById,
    required Map<String, StaffSummary> staffByUid,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activeSeries.isNotEmpty) ...[
          Text('Séries', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final series in activeSeries) ...[
            _SeriesTile(
              series: series,
              serviceName:
                  servicesById[series.serviceId]?.name ?? series.serviceId,
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
                    builder: (_) =>
                        OccurrenceDetailScreen(occurrenceId: occurrence.id),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        // No fim e com título próprio: uma série cancelada não é
        // horário, é histórico que o gestor pode querer reativar.
        if (cancelledSeries.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Canceladas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final series in cancelledSeries) ...[
            _SeriesTile(
              series: series,
              serviceName:
                  servicesById[series.serviceId]?.name ?? series.serviceId,
              instructorName: series.instructorId == null
                  ? null
                  : staffByUid[series.instructorId]?.name,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
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
