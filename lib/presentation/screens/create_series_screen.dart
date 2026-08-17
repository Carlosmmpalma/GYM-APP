import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/session_series.dart';
import 'manage_series_screen.dart';

final _conflictTimeFormat = DateFormat('HH:mm', 'pt_PT');

/// Fase 5 (UC17/UC19 atualizado) — criar uma aula/PT "só esta data" ou
/// "semanal, fixa" (série). Capacidade é sempre um número livre — os
/// chips Individual/Duo/Trio/Grupo só pré-preenchem o campo, nunca um
/// enum persistido (nota de arquitetura do UC19). Suporta também o
/// modelo híbrido: pré-atribuir membros elegíveis já aqui, deixando o
/// resto da capacidade aberta para auto-marcação.
class CreateSeriesScreen extends ConsumerStatefulWidget {
  const CreateSeriesScreen({super.key});

  @override
  ConsumerState<CreateSeriesScreen> createState() => _CreateSeriesScreenState();
}

class _CreateSeriesScreenState extends ConsumerState<CreateSeriesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _durationController = TextEditingController(text: '60');
  final _capacityController = TextEditingController(text: '1');

  bool _recurring = true;
  Service? _service;
  String? _instructorId;
  String? _modalityId;
  int _dayOfWeek = DateTime.monday;
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  final Set<String> _preAssignedMemberIds = {};

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _durationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  int get _capacity => int.tryParse(_capacityController.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nova aula / PT')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Só esta data')),
                  ButtonSegment(value: true, label: Text('Semanal, fixa')),
                ],
                selected: {_recurring},
                onSelectionChanged: (s) => setState(() => _recurring = s.first),
              ),
              const SizedBox(height: 16),
              servicesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Text('Erro a carregar serviços: $error'),
                data: (services) {
                  final active = services.where((s) => s.active).toList();
                  return DropdownButtonFormField<Service>(
                    initialValue: _service,
                    decoration: const InputDecoration(labelText: 'Serviço'),
                    items: active
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _service = v;
                      _modalityId = null;
                      _preAssignedMemberIds.clear();
                    }),
                    validator: (v) => v == null ? 'Escolhe um serviço' : null,
                  );
                },
              ),
              if (_service != null) ...[
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final modalitiesAsync = ref.watch(modalitiesProvider);
                    final options = (modalitiesAsync.valueOrNull ?? const [])
                        .where((m) =>
                            m.active && m.serviceIds.contains(_service!.id))
                        .toList();
                    if (options.isEmpty) return const SizedBox.shrink();
                    return DropdownButtonFormField<String?>(
                      key: ValueKey('modality-${_service!.id}'),
                      initialValue: _modalityId,
                      decoration: const InputDecoration(
                          labelText: 'Modalidade (opcional)'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Sem modalidade')),
                        ...options.map(
                          (m) => DropdownMenuItem(
                              value: m.id, child: Text(m.name)),
                        ),
                      ],
                      onChanged: (v) => setState(() => _modalityId = v),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              staffAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Text('Erro a carregar instrutores: $error'),
                data: (staff) {
                  final instructors = staff
                      .where((s) => s.roles.contains(Role.instructor))
                      .toList();
                  return DropdownButtonFormField<String?>(
                    initialValue: _instructorId,
                    decoration: const InputDecoration(
                        labelText: 'Instrutor (opcional)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Sem instrutor definido')),
                      ...instructors.map(
                        (s) =>
                            DropdownMenuItem(value: s.uid, child: Text(s.name)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _instructorId = v),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_recurring) ...[
                DropdownButtonFormField<int>(
                  initialValue: _dayOfWeek,
                  decoration: const InputDecoration(labelText: 'Dia da semana'),
                  items: [
                    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                      DropdownMenuItem(value: d, child: Text(weekdayName(d))),
                  ],
                  onChanged: (v) => setState(() => _dayOfWeek = v!),
                ),
                const SizedBox(height: 16),
              ],
              _DatePickerTile(
                label: _recurring ? 'A partir de' : 'Data',
                date: _date,
                onPick: (picked) => setState(() => _date = picked),
              ),
              const SizedBox(height: 8),
              _TimePickerTile(
                time: _time,
                onPick: (picked) => setState(() => _time = picked),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _durationController,
                decoration:
                    const InputDecoration(labelText: 'Duração (minutos)'),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = int.tryParse((v ?? '').trim());
                  return (parsed == null || parsed <= 0)
                      ? 'Valor inválido'
                      : null;
                },
              ),
              if (_instructorId != null)
                _TimeConflictBanner(
                  recurring: _recurring,
                  instructorId: _instructorId!,
                  dayOfWeek: _recurring ? _dayOfWeek : _date.weekday,
                  date: _date,
                  time: _time,
                  durationMinutes:
                      int.tryParse(_durationController.text.trim()) ?? 0,
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  _CapacityPresetChip(
                      label: 'Individual',
                      value: 1,
                      controller: _capacityController),
                  _CapacityPresetChip(
                      label: 'Duo', value: 2, controller: _capacityController),
                  _CapacityPresetChip(
                      label: 'Trio', value: 3, controller: _capacityController),
                  _CapacityPresetChip(
                      label: 'Grupo (6)',
                      value: 6,
                      controller: _capacityController),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _capacityController,
                decoration: const InputDecoration(labelText: 'Capacidade'),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = int.tryParse((v ?? '').trim());
                  return (parsed == null || parsed <= 0)
                      ? 'Valor inválido'
                      : null;
                },
              ),
              if (_service != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Pré-atribuir membros (opcional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  _recurring
                      ? 'Ficam marcados automaticamente em CADA semana gerada.'
                      : 'Ficam marcados já nesta sessão.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _EligibleMembersPicker(
                  serviceId: _service!.id,
                  capacity: _capacity,
                  selected: _preAssignedMemberIds,
                  onChanged: (memberId, selected) => setState(() {
                    if (selected) {
                      _preAssignedMemberIds.add(memberId);
                    } else {
                      _preAssignedMemberIds.remove(memberId);
                    }
                  }),
                ),
              ],
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Criar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_service == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final duration = int.parse(_durationController.text.trim());
      final capacity = int.parse(_capacityController.text.trim());
      final startAt = DateTime(
          _date.year, _date.month, _date.day, _time.hour, _time.minute);
      final endAt = startAt.add(Duration(minutes: duration));

      if (_recurring) {
        await ref.read(sessionSeriesRepositoryProvider).createSeries(
              serviceId: _service!.id,
              instructorId: _instructorId,
              modalityId: _modalityId,
              dayOfWeek: _dayOfWeek,
              startTime:
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
              durationMinutes: duration,
              capacity: capacity,
              startDate: DateTime(_date.year, _date.month, _date.day),
              preAssignedMemberIds: _preAssignedMemberIds.toList(),
            );

        // Gera já as próximas ocorrências — sem isto, o Gestor cria a
        // série e não vê nada acontecer, sem saber que precisa de
        // carregar num botão à parte em SeriesDetailScreen (pedido
        // depois de testares a Fase 5). O cron diário
        // (generateRecurringOccurrences.ts) continua necessário a
        // seguir a isto, para ir empurrando o horizonte de 8 semanas à
        // medida que o tempo passa — isto só cobre o momento da
        // criação. Falha aqui não desfaz a série (já está criada);
        // "Gerar agora" em SeriesDetailScreen mantém-se como
        // ferramenta de apoio para este e outros casos (ex.: o cron
        // falhar nalgum dia).
        var generated = true;
        try {
          await ref.read(sessionSeriesRepositoryProvider).generateNow();
        } catch (_) {
          generated = false;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              generated
                  ? 'Série criada — as próximas ocorrências já foram geradas.'
                  : 'Série criada, mas não foi possível gerar as ocorrências '
                      'agora. Abre-a e usa "Gerar agora".',
            ),
          ),
        );
      } else {
        final occurrenceId = await ref
            .read(sessionOccurrenceRepositoryProvider)
            .createOccurrence(
              serviceId: _service!.id,
              instructorId: _instructorId,
              modalityId: _modalityId,
              startAt: startAt,
              endAt: endAt,
              capacity: capacity,
            );
        if (_preAssignedMemberIds.isNotEmpty) {
          await ref.read(sessionOccurrenceRepositoryProvider).assignMembers(
                occurrenceId: occurrenceId,
                memberIds: _preAssignedMemberIds.toList(),
              );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessão criada.')),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Não foi possível criar: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _CapacityPresetChip extends StatelessWidget {
  const _CapacityPresetChip({
    required this.label,
    required this.value,
    required this.controller,
  });

  final String label;
  final int value;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () => controller.text = value.toString(),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile(
      {required this.label, required this.date, required this.onPick});

  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('${date.day}/${date.month}/${date.year}'),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  const _TimePickerTile({required this.time, required this.onPick});

  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Hora'),
      subtitle: Text(time.format(context)),
      trailing: const Icon(Icons.access_time_outlined),
      onTap: () async {
        final picked =
            await showTimePicker(context: context, initialTime: time);
        if (picked != null) onPick(picked);
      },
    );
  }
}

/// Fase 8 (auditoria funcional) — aviso de conflito de horário. O
/// mockup ("Criar aula — recorrente") descreve "conflito de horário
/// com outra aula da MESMA SALA é sinalizado antes de guardar" — mas
/// nenhum documento técnico (Domain Model v1, Firestore Data Model v1,
/// Platform Foundation) modela uma entidade `Room`/`Sala`, e inventar
/// uma agora sem essa decisão seria fabricar dados que não existem.
/// Proxy real e defensável: avisar quando o MESMO INSTRUTOR já tem
/// outra aula sobreposta no horário — sinalizado aqui, não escondido.
/// Nunca bloqueia a criação, só avisa; a decisão final é sempre do
/// Gestor (mesmo espírito de "sinalizado, não escondido" já usado
/// noutras simplificações desta app).
class _TimeConflictBanner extends ConsumerWidget {
  const _TimeConflictBanner({
    required this.recurring,
    required this.instructorId,
    required this.dayOfWeek,
    required this.date,
    required this.time,
    required this.durationMinutes,
  });

  final bool recurring;
  final String instructorId;
  final int dayOfWeek;
  final DateTime date;
  final TimeOfDay time;
  final int durationMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (durationMinutes <= 0) return const SizedBox.shrink();
    final startMinutes = time.hour * 60 + time.minute;
    final endMinutes = startMinutes + durationMinutes;

    final servicesById = <String, Service>{
      for (final s
          in ref.watch(servicesProvider).valueOrNull ?? const <Service>[])
        s.id: s,
    };

    String? conflictLabel;

    if (recurring) {
      // Séries recorrentes com o mesmo instrutor, no mesmo dia da
      // semana — a série em si nunca é reservável (só as ocorrências
      // que gera), mas o padrão semanal já basta para detetar o
      // conflito sem precisar de olhar para ocorrências concretas.
      final series =
          ref.watch(seriesProvider).valueOrNull ?? const <SessionSeries>[];
      for (final s in series) {
        if (!s.isActive || s.instructorId != instructorId) continue;
        if (s.dayOfWeek != dayOfWeek) continue;
        final parts = s.startTime.split(':');
        final otherStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        final otherEnd = otherStart + s.durationMinutes;
        if (startMinutes < otherEnd && otherStart < endMinutes) {
          conflictLabel = '${servicesById[s.serviceId]?.name ?? s.serviceId} '
              '· ${weekdayName(s.dayOfWeek)} ${s.startTime}';
          break;
        }
      }
    } else {
      // "Só esta data" — compara contra ocorrências JÁ MATERIALIZADAS
      // (ad-hoc ou geradas por série, `allUpcomingOccurrencesProvider`
      // cobre ambas) no mesmo dia concreto.
      final occurrences =
          ref.watch(allUpcomingOccurrencesProvider).valueOrNull ??
              const <SessionOccurrence>[];
      for (final o in occurrences) {
        if (o.status != SessionOccurrenceStatus.scheduled) continue;
        if (o.instructorId != instructorId) continue;
        if (!_isSameDay(o.startAt, date)) continue;
        final otherStart = o.startAt.hour * 60 + o.startAt.minute;
        final otherEnd = o.endAt.hour * 60 + o.endAt.minute;
        if (startMinutes < otherEnd && otherStart < endMinutes) {
          conflictLabel = '${servicesById[o.serviceId]?.name ?? o.serviceId} '
              '· ${_conflictTimeFormat.format(o.startAt)}';
          break;
        }
      }
    }

    if (conflictLabel == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conflito de horário: este instrutor já tem "$conflictLabel" '
                  'à mesma hora. Podes continuar, mas confirma que não é um erro.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// UC08-A (fechado) — só mostra membros que já têm o serviço
/// contratado, nunca deixa sequer tentar escolher outro. Bloqueia
/// selecionar mais do que [capacity] (nenhuma vaga aberta sobra se
/// pré-atribuíres todas, mas nunca pode ultrapassar).
class _EligibleMembersPicker extends ConsumerWidget {
  const _EligibleMembersPicker({
    required this.serviceId,
    required this.capacity,
    required this.selected,
    required this.onChanged,
  });

  final String serviceId;
  final int capacity;
  final Set<String> selected;
  final void Function(String memberId, bool selected) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibleAsync = ref.watch(eligibleMembersProvider(serviceId));

    return eligibleAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Text('Erro a carregar membros elegíveis: $error'),
      data: (members) {
        if (members.isEmpty) {
          return const Text(
            'Nenhum membro tem ainda um plano ativo com acesso a este serviço.',
            style: TextStyle(fontStyle: FontStyle.italic),
          );
        }
        return Column(
          children: members
              .map(
                (m) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${m.name} (${m.memberNumber})'),
                  value: selected.contains(m.uid),
                  onChanged: (v) {
                    if (v == true && selected.length >= capacity) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Já pré-atribuíste $capacity membro(s) — é a capacidade máxima.',
                          ),
                        ),
                      );
                      return;
                    }
                    onChanged(m.uid, v ?? false);
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }
}
