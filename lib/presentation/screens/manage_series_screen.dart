import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/session_series.dart';
import 'create_series_screen.dart';
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
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (seriesList) {
          if (seriesList.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não existe nenhuma série. Usa o botão "+" para criar '
                  'a primeira aula/PT recorrente.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final servicesById = {
            for (final s in servicesAsync.valueOrNull ?? const []) s.id: s,
          };
          final staffByUid = {
            for (final s in staffAsync.valueOrNull ?? const []) s.uid: s,
          };
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: seriesList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final series = seriesList[index];
              final serviceName =
                  servicesById[series.serviceId]?.name ?? series.serviceId;
              final instructorName = series.instructorId == null
                  ? null
                  : staffByUid[series.instructorId]?.name;
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
                    MaterialPageRoute(
                        builder: (_) => SeriesDetailScreen(series: series)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Formato curto de data usado pelos ecrãs de séries/ocorrências.
final seriesDateFormat = DateFormat('EEE, d MMM · HH:mm', 'pt_PT');

String weekdayName(int dayOfWeek) => _weekdayNames[dayOfWeek] ?? '$dayOfWeek';
