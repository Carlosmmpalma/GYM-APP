import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/staff_summary.dart';
import 'occurrence_detail_screen.dart';

final _dayFormat = DateFormat('EEE, d MMM', 'pt_PT');
final _timeFormat = DateFormat('HH:mm', 'pt_PT');

/// Fase 6 (UC20) — "calendário do instrutor": próximas 2 semanas,
/// agrupadas por dia. Primeira área da app própria para um Instrutor —
/// até aqui só o Gestor tinha ecrãs de gestão (decisão explícita da
/// Fase 5, ver `manage_series_screen.dart`). Reaproveitado também pelo
/// Gestor (`instructorId: null` → vê TODAS as sessões, não só as de
/// um instrutor), a partir de `ManagerScreen` ("visão do gestor" nos
/// mockups é a mesma janela, sem filtro).
///
/// Toca numa sessão → `OccurrenceDetailScreen`, o mesmo ecrã de
/// presença/reduzir vagas/remarcar/cancelar/notificar já usado pela
/// Gestão — os mockups mostram estas ações também na secção
/// "Instrutor", não é um ecrã à parte.
class InstructorCalendarScreen extends ConsumerWidget {
  const InstructorCalendarScreen({super.key, this.instructorId});

  final String? instructorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occurrencesAsync = ref.watch(upcomingTwoWeeksOccurrencesProvider);
    final servicesAsync = ref.watch(servicesProvider);
    final modalitiesAsync = ref.watch(modalitiesProvider);
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(instructorId == null ? 'Calendário' : 'As minhas aulas'),
      ),
      body: occurrencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (occurrences) {
          final servicesById = <String, Service>{
            for (final s in servicesAsync.valueOrNull ?? const <Service>[])
              s.id: s,
          };
          final modalitiesById = <String, Modality>{
            for (final m in modalitiesAsync.valueOrNull ?? const <Modality>[])
              m.id: m,
          };
          final staffByUid = <String, StaffSummary>{
            for (final s in staffAsync.valueOrNull ?? const <StaffSummary>[])
              s.uid: s,
          };

          final filtered = (instructorId == null
              ? occurrences
              : occurrences
                  .where((o) => o.instructorId == instructorId)
                  .toList())
            ..sort((a, b) => a.startAt.compareTo(b.startAt));

          if (filtered.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sem sessões nas próximas 2 semanas.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final byDay = <DateTime, List<SessionOccurrence>>{};
          for (final occurrence in filtered) {
            final day = DateTime(
              occurrence.startAt.year,
              occurrence.startAt.month,
              occurrence.startAt.day,
            );
            (byDay[day] ??= []).add(occurrence);
          }
          final days = byDay.keys.toList()..sort();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final day in days) ...[
                Text(
                  _dayFormat.format(day),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final occurrence in byDay[day]!) ...[
                  Card(
                    child: ListTile(
                      title: Text(
                        servicesById[occurrence.serviceId]?.name ??
                            occurrence.serviceId,
                      ),
                      subtitle: Text(
                        [
                          _timeFormat.format(occurrence.startAt),
                          if (occurrence.modalityId != null)
                            modalitiesById[occurrence.modalityId]?.name ?? '',
                          if (instructorId == null &&
                              occurrence.instructorId != null)
                            staffByUid[occurrence.instructorId]?.name ?? '',
                          '${occurrence.activeBookingCount}/${occurrence.capacity} inscritos',
                          if (occurrence.status ==
                              SessionOccurrenceStatus.cancelled)
                            'cancelada',
                        ].where((p) => p.isNotEmpty).join(' · '),
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
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}
