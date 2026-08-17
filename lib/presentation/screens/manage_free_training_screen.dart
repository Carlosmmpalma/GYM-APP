import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/free_training_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/free_training_schedule.dart';
import '../../domain/entities/free_training_slot.dart';
import '../../domain/entities/service.dart';
import 'free_training_slot_detail_screen.dart';

final _dayFormat = DateFormat('EEE, d MMM', 'pt_PT');
final _timeFormat = DateFormat('HH:mm', 'pt_PT');
final _weekRangeFormat = DateFormat('d MMM', 'pt_PT');
const _weekdayLabels = {
  DateTime.monday: 'Seg',
  DateTime.tuesday: 'Ter',
  DateTime.wednesday: 'Qua',
  DateTime.thursday: 'Qui',
  DateTime.friday: 'Sex',
  DateTime.saturday: 'Sáb',
  DateTime.sunday: 'Dom',
};

/// Fase 7 (UC17-A fechado) — "Treino livre — configurar": o Gestor
/// gera/revê a sugestão automática (copiada da semana anterior),
/// ajusta os blocos, e só depois de "Aprovar e publicar semana" é que
/// fica visível ao Aluno (`FreeTrainingScreen`). Navegação semana a
/// semana, mesmo padrão do ecrã do Aluno.
class ManageFreeTrainingScreen extends ConsumerStatefulWidget {
  const ManageFreeTrainingScreen({super.key});

  @override
  ConsumerState<ManageFreeTrainingScreen> createState() =>
      _ManageFreeTrainingScreenState();
}

class _ManageFreeTrainingScreenState
    extends ConsumerState<ManageFreeTrainingScreen> {
  late DateTime _weekAnchor = DateTime.now();
  Service? _serviceForNewWeek;
  bool _suggesting = false;

  @override
  Widget build(BuildContext context) {
    final weekId = weekIdForDate(_weekAnchor);
    final weekRange = isoWeekRange(_weekAnchor);
    final scheduleAsync = ref.watch(freeTrainingScheduleProvider(weekId));

    return Scaffold(
      appBar: AppBar(title: const Text('Treino livre')),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _weekAnchor =
                    _weekAnchor.subtract(const Duration(days: 7))),
              ),
              Text(
                '${_weekRangeFormat.format(weekRange.start)} – '
                '${_weekRangeFormat.format(weekRange.end)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                tooltip: 'Semana seguinte',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() =>
                    _weekAnchor = _weekAnchor.add(const Duration(days: 7))),
              ),
            ],
          ),
          Expanded(
            child: scheduleAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Erro: $error')),
              data: (schedule) {
                if (schedule == null) {
                  return _NoScheduleView(
                    weekAnchor: _weekAnchor,
                    selectedService: _serviceForNewWeek,
                    suggesting: _suggesting,
                    onServiceChanged: (s) =>
                        setState(() => _serviceForNewWeek = s),
                    onSuggest: _suggest,
                  );
                }
                return _ScheduleView(weekId: weekId, schedule: schedule);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _suggest() async {
    final service = _serviceForNewWeek;
    if (service == null) return;
    setState(() => _suggesting = true);
    try {
      await ref.read(freeTrainingRepositoryProvider).suggestSchedule(
            weekStart: _weekAnchor,
            serviceId: service.id,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar a grelha: $e')),
      );
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }
}

class _NoScheduleView extends ConsumerWidget {
  const _NoScheduleView({
    required this.weekAnchor,
    required this.selectedService,
    required this.suggesting,
    required this.onServiceChanged,
    required this.onSuggest,
  });

  final DateTime weekAnchor;
  final Service? selectedService;
  final bool suggesting;
  final ValueChanged<Service?> onServiceChanged;
  final VoidCallback onSuggest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Esta semana ainda não tem nenhuma grelha de treino livre.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          servicesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (error, stack) => Text('Erro: $error'),
            data: (services) {
              final active = services.where((s) => s.active).toList();
              return DropdownButtonFormField<Service>(
                initialValue: selectedService,
                decoration: const InputDecoration(
                    labelText: 'Serviço (ex.: Treino sem acompanhamento)'),
                items: active
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: onServiceChanged,
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                (selectedService == null || suggesting) ? null : onSuggest,
            child: suggesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Gerar grelha desta semana'),
          ),
        ],
      ),
    );
  }
}

class _ScheduleView extends ConsumerWidget {
  const _ScheduleView({required this.weekId, required this.schedule});

  final String weekId;
  final FreeTrainingSchedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotsAsync = ref.watch(freeTrainingSlotsProvider(weekId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (schedule.status == FreeTrainingScheduleStatus.suggested)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '✨ Sugestão automática — por aprovar. Baseada na semana '
                'anterior. Os alunos ainda não veem esta grelha.',
              ),
            ),
          )
        else if (schedule.status == FreeTrainingScheduleStatus.draft)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Rascunho — ainda não publicada, os alunos não veem isto.'),
            ),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('✓ Publicada — visível aos alunos.'),
            ),
          ),
        const SizedBox(height: 12),
        slotsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Erro: $error'),
          data: (slots) {
            final byDay = <DateTime, List<FreeTrainingSlot>>{};
            for (final slot in slots) {
              final day = DateTime(
                  slot.startAt.year, slot.startAt.month, slot.startAt.day);
              (byDay[day] ??= []).add(slot);
            }
            final days = byDay.keys.toList()..sort();

            return Column(
              children: [
                for (final day in days) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _dayFormat.format(day),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final slot in byDay[day]!) ...[
                    Card(
                      child: ListTile(
                        title: Text(
                          '${_timeFormat.format(slot.startAt)}–${_timeFormat.format(slot.endAt)}',
                        ),
                        subtitle: Text(
                          '${slot.activeBookingCount}/${slot.capacity} inscritos',
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                FreeTrainingSlotDetailScreen(slot: slot),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                switch (action) {
                                  case 'edit':
                                    _editSlot(context, ref, slot);
                                  case 'delete':
                                    _deleteSlot(context, ref, slot);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit', child: Text('Editar')),
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled: schedule.status !=
                                          FreeTrainingScheduleStatus
                                              .published &&
                                      slot.activeBookingCount == 0,
                                  child: const Text('Remover'),
                                ),
                              ],
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                OutlinedButton.icon(
                  onPressed: () => _addBlock(context, ref, slots),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar bloco de horário'),
                ),
                const SizedBox(height: 16),
                if (schedule.status != FreeTrainingScheduleStatus.published)
                  FilledButton.icon(
                    onPressed:
                        slots.isEmpty ? null : () => _publish(context, ref),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprovar e publicar semana'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _addBlock(
    BuildContext context,
    WidgetRef ref,
    List<FreeTrainingSlot> existingSlots,
  ) async {
    final result = await showDialog<_NewBlock>(
      context: context,
      builder: (_) => const _AddSlotBlockDialog(),
    );
    if (result == null) return;

    final monday = isoWeekRange(schedule.weekStart).start;
    final repository = ref.read(freeTrainingRepositoryProvider);
    try {
      for (final weekday in result.weekdays) {
        final day = monday.add(Duration(days: weekday - DateTime.monday));
        await repository.createSlot(
          weekId: weekId,
          serviceId: result.serviceId,
          startAt: DateTime(day.year, day.month, day.day, result.start.hour,
              result.start.minute),
          endAt: DateTime(
              day.year, day.month, day.day, result.end.hour, result.end.minute),
          capacity: result.capacity,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar o bloco: $e')),
      );
    }
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(freeTrainingRepositoryProvider).publishSchedule(weekId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Semana publicada — já visível aos alunos.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível publicar: $e')),
      );
    }
  }

  Future<void> _editSlot(
    BuildContext context,
    WidgetRef ref,
    FreeTrainingSlot slot,
  ) async {
    final result =
        await showDialog<({TimeOfDay start, TimeOfDay end, int capacity})>(
      context: context,
      builder: (_) => _EditSlotDialog(slot: slot),
    );
    if (result == null) return;

    final day =
        DateTime(slot.startAt.year, slot.startAt.month, slot.startAt.day);
    try {
      await ref.read(freeTrainingRepositoryProvider).updateSlot(
            weekId: weekId,
            slotId: slot.id,
            startAt: DateTime(day.year, day.month, day.day, result.start.hour,
                result.start.minute),
            endAt: DateTime(day.year, day.month, day.day, result.end.hour,
                result.end.minute),
            capacity: result.capacity,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível editar: $e')),
      );
    }
  }

  Future<void> _deleteSlot(
    BuildContext context,
    WidgetRef ref,
    FreeTrainingSlot slot,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover este bloco?'),
        content: const Text(
          'Só é possível remover blocos antes de a semana ser publicada, e '
          'sem ninguém marcado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(freeTrainingRepositoryProvider).deleteSlot(
            weekId: weekId,
            slotId: slot.id,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível remover: $e')),
      );
    }
  }
}

class _EditSlotDialog extends StatefulWidget {
  const _EditSlotDialog({required this.slot});

  final FreeTrainingSlot slot;

  @override
  State<_EditSlotDialog> createState() => _EditSlotDialogState();
}

class _EditSlotDialogState extends State<_EditSlotDialog> {
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.slot.startAt);
  late TimeOfDay _end = TimeOfDay.fromDateTime(widget.slot.endAt);
  late final _capacityController =
      TextEditingController(text: widget.slot.capacity.toString());

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar bloco'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hora de início'),
            trailing: Text(_start.format(context)),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _start);
              if (picked != null) setState(() => _start = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hora de fim'),
            trailing: Text(_end.format(context)),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _end);
              if (picked != null) setState(() => _end = picked);
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
            Navigator.of(context)
                .pop((start: _start, end: _end, capacity: capacity));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _NewBlock {
  const _NewBlock({
    required this.weekdays,
    required this.start,
    required this.end,
    required this.capacity,
    required this.serviceId,
  });

  final Set<int> weekdays;
  final TimeOfDay start;
  final TimeOfDay end;
  final int capacity;
  final String serviceId;
}

class _AddSlotBlockDialog extends ConsumerStatefulWidget {
  const _AddSlotBlockDialog();

  @override
  ConsumerState<_AddSlotBlockDialog> createState() =>
      _AddSlotBlockDialogState();
}

class _AddSlotBlockDialogState extends ConsumerState<_AddSlotBlockDialog> {
  final Set<int> _weekdays = {};
  TimeOfDay _start = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 8, minute: 0);
  final _capacityController = TextEditingController(text: '10');
  Service? _service;

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);

    return AlertDialog(
      title: const Text('Novo bloco de horário'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dias da semana'),
            Wrap(
              spacing: 4,
              children: _weekdayLabels.entries
                  .map(
                    (entry) => FilterChip(
                      label: Text(entry.value),
                      selected: _weekdays.contains(entry.key),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _weekdays.add(entry.key);
                        } else {
                          _weekdays.remove(entry.key);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hora de início'),
              trailing: Text(_start.format(context)),
              onTap: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: _start);
                if (picked != null) setState(() => _start = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hora de fim'),
              trailing: Text(_end.format(context)),
              onTap: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: _end);
                if (picked != null) setState(() => _end = picked);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _capacityController,
              decoration: const InputDecoration(labelText: 'Capacidade'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            servicesAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => Text('Erro: $error'),
              data: (services) {
                final active = services.where((s) => s.active).toList();
                return DropdownButtonFormField<Service>(
                  initialValue: _service,
                  decoration: const InputDecoration(labelText: 'Serviço'),
                  items: active
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s.name)))
                      .toList(),
                  onChanged: (s) => setState(() => _service = s),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canSubmit() ? _submit : null,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }

  bool _canSubmit() {
    final capacity = int.tryParse(_capacityController.text.trim());
    return _weekdays.isNotEmpty &&
        _service != null &&
        capacity != null &&
        capacity > 0;
  }

  void _submit() {
    Navigator.of(context).pop(
      _NewBlock(
        weekdays: _weekdays,
        start: _start,
        end: _end,
        capacity: int.parse(_capacityController.text.trim()),
        serviceId: _service!.id,
      ),
    );
  }
}
