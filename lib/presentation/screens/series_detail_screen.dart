import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/session_series.dart';
import 'manage_series_screen.dart';

/// Fase 5 — "ajustar uma semana da série": resumo da [SessionSeries] +
/// lista das ocorrências já materializadas (`seriesOccurrencesProvider`),
/// cada uma editável/cancelável isoladamente sem afetar a série
/// (Firestore Data Model v1 §22). Também onde o Gestor cancela a série
/// inteira (futuras ocorrências cascata, passadas intocadas) e força
/// uma geração imediata sem esperar pelo cron diário.
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({super.key, required this.series});

  final SessionSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);
    final occurrencesAsync = ref.watch(seriesOccurrencesProvider(series.id));
    final servicesById = {
      for (final s in servicesAsync.valueOrNull ?? const []) s.id: s,
    };
    final serviceName =
        servicesById[series.serviceId]?.name ?? series.serviceId;

    return Scaffold(
      appBar: AppBar(title: Text(serviceName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${weekdayName(series.dayOfWeek)} · ${series.startTime} · '
                    '${series.durationMinutes} min · ${series.capacityLabel}',
                  ),
                  const SizedBox(height: 4),
                  Text(series.isActive ? 'Série ativa' : 'Série cancelada'),
                  if (series.preAssignedMemberIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${series.preAssignedMemberIds.length} membro(s) pré-atribuído(s) '
                      'a cada semana gerada.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      series.isActive ? () => _generateNow(context, ref) : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Gerar agora'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: series.isActive
                      ? () => _cancelSeries(context, ref)
                      : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar série'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Ocorrências geradas',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          occurrencesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Text('Erro: $error'),
            data: (occurrences) {
              if (occurrences.isEmpty) {
                return const Text(
                  'Ainda não há ocorrências geradas. Usa "Gerar agora".',
                  style: TextStyle(fontStyle: FontStyle.italic),
                );
              }
              return Column(
                children: occurrences
                    .map((occ) => _OccurrenceTile(
                        occurrence: occ, serviceId: series.serviceId))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _generateNow(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(sessionSeriesRepositoryProvider).generateNow();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Geração pedida — confirma as novas ocorrências abaixo.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar: $e')),
      );
    }
  }

  Future<void> _cancelSeries(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar série?'),
        content: const Text(
          'A série deixa de gerar novas ocorrências e as ocorrências futuras já '
          'geradas são canceladas. Ocorrências passadas não são afetadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar série'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(sessionSeriesRepositoryProvider).cancelSeries(series.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Série cancelada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar: $e')),
      );
    }
  }
}

class _OccurrenceTile extends ConsumerWidget {
  const _OccurrenceTile({required this.occurrence, required this.serviceId});

  final SessionOccurrence occurrence;
  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cancelled = occurrence.status == SessionOccurrenceStatus.cancelled;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(seriesDateFormat.format(occurrence.startAt)),
        subtitle: Text(
          cancelled
              ? 'Cancelada'
              : '${occurrence.activeBookingCount}/${occurrence.capacity} marcações',
        ),
        trailing: cancelled
            ? null
            : PopupMenuButton<String>(
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _edit(context, ref);
                    case 'assign':
                      _assign(context, ref);
                    case 'cancel':
                      _cancel(context, ref);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'edit', child: Text('Editar esta ocorrência')),
                  PopupMenuItem(
                      value: 'assign', child: Text('Adicionar membro')),
                  PopupMenuItem(
                      value: 'cancel', child: Text('Cancelar só esta')),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({DateTime startAt, int capacity})>(
      context: context,
      builder: (_) => _EditOccurrenceDialog(occurrence: occurrence),
    );
    if (result == null) return;
    try {
      await ref.read(sessionOccurrenceRepositoryProvider).updateOccurrence(
            occurrenceId: occurrence.id,
            startAt: result.startAt,
            endAt: result.startAt
                .add(occurrence.endAt.difference(occurrence.startAt)),
            capacity: result.capacity,
            instructorId: occurrence.instructorId,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível editar: $e')),
      );
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar só esta ocorrência?'),
        content: occurrence.activeBookingCount > 0
            ? Text(
                'Esta ocorrência tem ${occurrence.activeBookingCount} marcação(ões) ativa(s). '
                'Cancelar aqui NÃO cancela nem notifica essas marcações automaticamente '
                '(isso é Fase 6) — a série continua a gerar as próximas semanas normalmente.',
              )
            : const Text(
                'A série continua a gerar as próximas semanas normalmente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(sessionOccurrenceRepositoryProvider)
          .cancelOccurrence(occurrence.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar: $e')),
      );
    }
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final memberIds = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _AssignMemberDialog(serviceId: serviceId, occurrence: occurrence),
    );
    if (memberIds == null || memberIds.isEmpty) return;

    try {
      final results =
          await ref.read(sessionOccurrenceRepositoryProvider).assignMembers(
                occurrenceId: occurrence.id,
                memberIds: memberIds,
              );
      final assigned = results.values.where((ok) => ok).length;
      final failed = results.length - assigned;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? '$assigned membro(s) atribuído(s).'
                : '$assigned atribuído(s), $failed não foi possível (sem vaga ou sem plano ativo).',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atribuir: $e')),
      );
    }
  }
}

class _EditOccurrenceDialog extends StatefulWidget {
  const _EditOccurrenceDialog({required this.occurrence});

  final SessionOccurrence occurrence;

  @override
  State<_EditOccurrenceDialog> createState() => _EditOccurrenceDialogState();
}

class _EditOccurrenceDialogState extends State<_EditOccurrenceDialog> {
  late DateTime _date = widget.occurrence.startAt;
  late TimeOfDay _time = TimeOfDay.fromDateTime(widget.occurrence.startAt);
  late final _capacityController =
      TextEditingController(text: widget.occurrence.capacity.toString());

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar esta ocorrência'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Altera só esta semana — a série e as restantes ocorrências não mudam.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data'),
            subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hora'),
            subtitle: Text(_time.format(context)),
            trailing: const Icon(Icons.access_time_outlined),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
          ),
          TextField(
            controller: _capacityController,
            decoration: const InputDecoration(labelText: 'Capacidade'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final capacity = int.tryParse(_capacityController.text.trim());
            if (capacity == null || capacity <= 0) return;
            final startAt = DateTime(
                _date.year, _date.month, _date.day, _time.hour, _time.minute);
            Navigator.of(context).pop((startAt: startAt, capacity: capacity));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AssignMemberDialog extends ConsumerStatefulWidget {
  const _AssignMemberDialog(
      {required this.serviceId, required this.occurrence});

  final String serviceId;
  final SessionOccurrence occurrence;

  @override
  ConsumerState<_AssignMemberDialog> createState() =>
      _AssignMemberDialogState();
}

class _AssignMemberDialogState extends ConsumerState<_AssignMemberDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final eligibleAsync = ref.watch(eligibleMembersProvider(widget.serviceId));
    final availableSlots = widget.occurrence.availableSlots;

    return AlertDialog(
      title: const Text('Adicionar membro'),
      content: SizedBox(
        width: double.maxFinite,
        child: eligibleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Erro: $error'),
          data: (members) {
            if (members.isEmpty) {
              return const Text(
                'Nenhum membro tem ainda um plano ativo com acesso a este serviço.',
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$availableSlots vaga(s) disponível(eis).'),
                  for (final member in members)
                    CheckboxListTile(
                      title: Text('${member.name} (${member.memberNumber})'),
                      value: _selected.contains(member.uid),
                      onChanged: (v) {
                        if (v == true && _selected.length >= availableSlots) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Não há mais vagas disponíveis.')),
                          );
                          return;
                        }
                        setState(() {
                          if (v == true) {
                            _selected.add(member.uid);
                          } else {
                            _selected.remove(member.uid);
                          }
                        });
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
