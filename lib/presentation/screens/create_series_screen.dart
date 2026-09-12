import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/session_series.dart';
import '../widgets/design_system.dart';
import 'manage_series_screen.dart';
import '../../core/utils/time_range.dart';
import '../widgets/time_range_field.dart';

final _conflictTimeFormat = DateFormat('HH:mm', 'pt_PT');

/// Fase 5 (UC17/UC19 atualizado) — criar uma aula/PT "só esta data" ou
/// "semanal, fixa" (série). Capacidade é sempre um número livre — os
/// chips Individual/Duo/Trio/Grupo só pré-preenchem o campo, nunca um
/// enum persistido (nota de arquitetura do UC19). Suporta também o
/// modelo híbrido: pré-atribuir membros elegíveis já aqui, deixando o
/// resto da capacidade aberta para auto-marcação.
class CreateSeriesScreen extends ConsumerStatefulWidget {
  const CreateSeriesScreen({
    super.key,
    this.restrictedServiceIds,
    this.lockedInstructorId,
  });

  /// Fase 11 — quando é um Instrutor a criar, só pode escolher entre os
  /// serviços que o Gestor lhe associou. `null` = sem restrição (é o
  /// Gestor a criar).
  final Set<String>? restrictedServiceIds;

  /// Quando definido, a aula é obrigatoriamente deste instrutor e o
  /// campo deixa de ser escolha. `null` = o Gestor escolhe.
  final String? lockedInstructorId;

  @override
  ConsumerState<CreateSeriesScreen> createState() => _CreateSeriesScreenState();
}

class _CreateSeriesScreenState extends ConsumerState<CreateSeriesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _capacityController = TextEditingController(text: '1');

  bool _recurring = true;
  Service? _service;

  /// Quando o ecrã é aberto por um Instrutor, nasce já com ele — é a
  /// única hipótese que as Security Rules aceitam, e sem isto a série
  /// seria criada sem instrutor e recusada pelo servidor.
  late String? _instructorId = widget.lockedInstructorId;
  String? _modalityId;
  int _dayOfWeek = DateTime.monday;
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);

  /// A hora a que a aula acaba.
  ///
  /// Era um campo de texto a pedir a duração EM MINUTOS. Quem marca uma
  /// aula pensa "das seis às sete", não "sessenta" — e escrever o
  /// número obrigava a fazer a conta de cabeça sem nunca ver a que
  /// horas a aula acabava. A duração continua a ser o que se guarda
  /// (`durationMinutes`), só deixou de ser o que se escreve.
  TimeOfDay _endTime = const TimeOfDay(hour: 19, minute: 0);

  int get _durationMinutes => durationInMinutes(_time, _endTime);

  /// O formulário abre com segunda-feira às 18:00 — valores plausíveis
  /// para começar, mas que o Gestor ainda não escolheu.
  ///
  /// Sem isto, o aviso de conflito disparava mal se escolhesse o
  /// instrutor, a comparar com um horário que ninguém tinha indicado.
  /// Quem já tem uma aula às segundas às 18:00 via o aviso em TODAS as
  /// criações seguintes, antes sequer de dizer quando queria a aula —
  /// e um aviso que aparece sempre deixa de ser lido. O aviso só faz
  /// sentido depois de o horário ser uma escolha.
  ///
  /// O que não muda: ao gravar, o conflito é reavaliado de qualquer
  /// forma (ver `_submit`), tenha o horário sido mexido ou não.
  bool _scheduleTouched = false;
  final Set<String> _preAssignedMemberIds = {};

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
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
                onSelectionChanged: (s) => setState(() {
                  _recurring = s.first;
                  _scheduleTouched = true;
                }),
              ),
              const SizedBox(height: 16),
              servicesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => ErrorState(
                  error: error,
                  message: 'Não foi possível carregar serviços.',
                  compact: true,
                ),
                data: (services) {
                  var active = services.where((s) => s.active).toList();
                  // Fase 11 — um Instrutor só vê os serviços que o
                  // Gestor lhe associou. As Security Rules recusam os
                  // outros de qualquer forma; mostrar o que vai ser
                  // recusado seria oferecer uma porta fechada.
                  if (widget.restrictedServiceIds != null) {
                    active = active
                        .where(
                            (s) => widget.restrictedServiceIds!.contains(s.id))
                        .toList();
                  }
                  if (active.isEmpty) {
                    return const EmptyState(
                      icon: Icons.lock_outline,
                      title: 'Sem serviços atribuídos',
                      message: 'Ainda não tens nenhum serviço associado ao '
                          'teu perfil, por isso não podes criar aulas. Pede '
                          'ao Gestor para te atribuir os que lecionas.',
                    );
                  }
                  return DropdownButtonFormField<Service>(
                    isExpanded: true,
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
                      isExpanded: true,
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
                error: (error, stack) => ErrorState(
                  error: error,
                  message: 'Não foi possível carregar instrutores.',
                  compact: true,
                ),
                data: (staff) {
                  // Um Instrutor cria em nome PRÓPRIO e mais nada — as
                  // Rules verificam-no. Sem escolha para fazer, o campo
                  // deixa de ser um dropdown e passa a dizer o que é.
                  if (widget.lockedInstructorId != null) {
                    final me = staff.firstWhere(
                      (s) => s.uid == widget.lockedInstructorId,
                      orElse: () => staff.first,
                    );
                    return InputDecorator(
                      decoration: const InputDecoration(labelText: 'Instrutor'),
                      child: Text(me.name),
                    );
                  }
                  final instructors = staff
                      .where((s) => s.roles.contains(Role.instructor))
                      .toList();
                  return DropdownButtonFormField<String?>(
                    isExpanded: true,
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
                  isExpanded: true,
                  initialValue: _dayOfWeek,
                  decoration: const InputDecoration(labelText: 'Dia da semana'),
                  items: [
                    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                      DropdownMenuItem(value: d, child: Text(weekdayName(d))),
                  ],
                  onChanged: (v) => setState(() {
                    _dayOfWeek = v!;
                    _scheduleTouched = true;
                  }),
                ),
                const SizedBox(height: 16),
              ],
              _DatePickerTile(
                label: _recurring ? 'A partir de' : 'Data',
                date: _date,
                onPick: (picked) => setState(() {
                  _date = picked;
                  _scheduleTouched = true;
                }),
              ),
              const SizedBox(height: 12),
              TimeRangeField(
                start: _time,
                end: _endTime,
                onChanged: (start, end) => setState(() {
                  _time = start;
                  _endTime = end;
                  _scheduleTouched = true;
                }),
              ),
              if (_instructorId != null && _scheduleTouched)
                _TimeConflictBanner(
                  recurring: _recurring,
                  instructorId: _instructorId!,
                  dayOfWeek: _recurring ? _dayOfWeek : _date.weekday,
                  date: _date,
                  time: _time,
                  durationMinutes: _durationMinutes,
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
                decoration:
                    InputDecoration(labelText: requiredLabel('Capacidade')),
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

  /// `true` = pode seguir. Ou não há conflito, ou o Gestor confirmou.
  ///
  /// O aviso no formulário pode nunca ter sido visto — o horário pode
  /// ter ficado nos valores por omissão, ou o aviso pode estar fora do
  /// ecrã no momento de gravar. Criar uma aula sobreposta em silêncio é
  /// o pior dos resultados: ninguém dá por isso até a sala ter duas
  /// turmas e um instrutor.
  ///
  /// As listas são lidas com `.future`, não com `valueOrNull`: se
  /// nenhum widget as estiver a observar neste momento (é o caso
  /// enquanto o aviso está escondido), `valueOrNull` devolve `null` e a
  /// verificação passava a dizer sempre "sem conflito" — exatamente
  /// quando era mais precisa.
  Future<bool> _confirmScheduleConflict() async {
    final instructorId = _instructorId;
    if (instructorId == null) return true;

    final duration = _durationMinutes;
    final startMinutes = _time.hour * 60 + _time.minute;

    final List<String> conflicts;
    try {
      conflicts = findScheduleConflicts(
        recurring: _recurring,
        instructorId: instructorId,
        dayOfWeek: _recurring ? _dayOfWeek : _date.weekday,
        date: _date,
        startMinutes: startMinutes,
        endMinutes: startMinutes + duration,
        series: _recurring
            ? await ref.read(seriesProvider.future)
            : const <SessionSeries>[],
        occurrences: _recurring
            ? const <SessionOccurrence>[]
            : await ref.read(allUpcomingOccurrencesProvider.future),
        servicesById: {
          for (final service in await ref.read(servicesProvider.future))
            service.id: service,
        },
      );
    } catch (_) {
      // Isto é um aviso, não uma invariante do domínio — se as listas
      // não vierem (rede em baixo), o Gestor não fica impedido de
      // criar a aula por causa de uma verificação de cortesia.
      return true;
    }

    if (conflicts.isEmpty || !mounted) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Conflito de horário'),
        content: Text(
          'Este instrutor já tem a esta hora:\n\n'
          '${conflicts.map((c) => '•  $c').join('\n')}\n\n'
          'Queres criar esta aula na mesma?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Rever'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Criar mesmo assim'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_service == null) return;
    // O par de horas não vive dentro do `Form`, por isso a validação
    // acima não lhe toca. Sem isto dava para gravar uma aula com
    // duração negativa — foi assim que apareceram blocos de treino
    // livre das 08:10 às 08:00.
    if (!endsAfterStart(_time, _endTime)) {
      setState(() => _error = 'A hora de fim tem de ser depois da de início.');
      return;
    }
    if (!await _confirmScheduleConflict()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final duration = _durationMinutes;
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
      setState(() => _error = userFacingError(e,
          fallback: 'Não foi possível criar. Tenta outra vez.'));
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

/// Devolve a descrição da aula em conflito, ou `null` se não houver.
///
/// Vive fora do widget porque é usada em dois sítios com exigências
/// diferentes: o aviso enquanto se preenche o formulário, e a
/// confirmação ao gravar. Ter isto duplicado seria a forma mais certa
/// de os dois deixarem de concordar.
@visibleForTesting

/// Tudo o que este instrutor já tem a colidir com o horário indicado.
///
/// Devolvia só a PRIMEIRA colisão. Num estúdio com um instrutor só —
/// que é o caso comum no início — isso escondia metade da história:
/// quem tinha duas aulas iguais à segunda às 18:00 via um aviso a falar
/// de uma, criava a terceira, e continuava sem perceber o que se
/// passava naquele horário.
@visibleForTesting
List<String> findScheduleConflicts({
  required bool recurring,
  required String instructorId,
  required int dayOfWeek,
  required DateTime date,
  required int startMinutes,
  required int endMinutes,
  required List<SessionSeries> series,
  required List<SessionOccurrence> occurrences,
  required Map<String, Service> servicesById,
}) {
  if (endMinutes <= startMinutes) return const [];
  final found = <String>[];

  if (recurring) {
    // Séries recorrentes com o mesmo instrutor, no mesmo dia da
    // semana — a série em si nunca é reservável (só as ocorrências que
    // gera), mas o padrão semanal já basta para detetar o conflito sem
    // precisar de olhar para ocorrências concretas.
    for (final s in series) {
      if (!s.isActive || s.instructorId != instructorId) continue;
      if (s.dayOfWeek != dayOfWeek) continue;
      final parts = s.startTime.split(':');
      final otherStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      final otherEnd = otherStart + s.durationMinutes;
      if (startMinutes < otherEnd && otherStart < endMinutes) {
        found.add('${servicesById[s.serviceId]?.name ?? s.serviceId} '
            '· ${weekdayName(s.dayOfWeek)} ${s.startTime}');
      }
    }
    return found;
  }

  // "Só esta data" — compara contra ocorrências JÁ MATERIALIZADAS
  // (ad-hoc ou geradas por série, `allUpcomingOccurrencesProvider`
  // cobre ambas) no mesmo dia concreto.
  for (final o in occurrences) {
    if (o.status != SessionOccurrenceStatus.scheduled) continue;
    if (o.instructorId != instructorId) continue;
    if (!_isSameDay(o.startAt, date)) continue;
    final otherStart = o.startAt.hour * 60 + o.startAt.minute;
    final otherEnd = o.endAt.hour * 60 + o.endAt.minute;
    if (startMinutes < otherEnd && otherStart < endMinutes) {
      found.add('${servicesById[o.serviceId]?.name ?? o.serviceId} '
          '· ${_conflictTimeFormat.format(o.startAt)}');
    }
  }
  return found;
}

/// O horário completo deste instrutor naquele dia, colida ou não.
///
/// É a informação que faltava: o aviso dizia "há conflito" sem mostrar
/// o que lá está, e quem o lê não tem como escolher uma hora livre sem
/// sair do ecrã e ir ver o calendário.
@visibleForTesting
List<String> instructorDaySchedule({
  required bool recurring,
  required String instructorId,
  required int dayOfWeek,
  required DateTime date,
  required List<SessionSeries> series,
  required List<SessionOccurrence> occurrences,
  required Map<String, Service> servicesById,
}) {
  final entries = <(int, String)>[];

  if (recurring) {
    for (final s in series) {
      if (!s.isActive || s.instructorId != instructorId) continue;
      if (s.dayOfWeek != dayOfWeek) continue;
      final parts = s.startTime.split(':');
      final start = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      entries.add((
        start,
        '${s.startTime}–${_minutesLabel(start + s.durationMinutes)} · '
            '${servicesById[s.serviceId]?.name ?? s.serviceId}'
      ));
    }
  } else {
    for (final o in occurrences) {
      if (o.status != SessionOccurrenceStatus.scheduled) continue;
      if (o.instructorId != instructorId) continue;
      if (!_isSameDay(o.startAt, date)) continue;
      entries.add((
        o.startAt.hour * 60 + o.startAt.minute,
        '${_conflictTimeFormat.format(o.startAt)}–'
            '${_conflictTimeFormat.format(o.endAt)} · '
            '${servicesById[o.serviceId]?.name ?? o.serviceId}'
      ));
    }
  }

  entries.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final entry in entries) entry.$2];
}

String _minutesLabel(int minutes) {
  final capped = minutes.clamp(0, 24 * 60);
  return '${(capped ~/ 60).toString().padLeft(2, '0')}:'
      '${(capped % 60).toString().padLeft(2, '0')}';
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

    // Só o lado que interessa é observado: subscrever as duas listas
    // seria um listener de Firestore a mais, aberto durante todo o
    // preenchimento do formulário.
    final seriesList = recurring
        ? ref.watch(seriesProvider).valueOrNull ?? const <SessionSeries>[]
        : const <SessionSeries>[];
    final occurrenceList = recurring
        ? const <SessionOccurrence>[]
        : ref.watch(allUpcomingOccurrencesProvider).valueOrNull ??
            const <SessionOccurrence>[];

    final conflicts = findScheduleConflicts(
      recurring: recurring,
      instructorId: instructorId,
      dayOfWeek: dayOfWeek,
      date: date,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      series: seriesList,
      occurrences: occurrenceList,
      servicesById: servicesById,
    );

    if (conflicts.isEmpty) return const SizedBox.shrink();

    // O dia inteiro, e não só o que colide. O aviso antigo dizia "há
    // conflito" e obrigava a sair do ecrã para perceber onde estava o
    // espaço livre.
    final daySchedule = instructorDaySchedule(
      recurring: recurring,
      instructorId: instructorId,
      dayOfWeek: dayOfWeek,
      date: date,
      series: seriesList,
      occurrences: occurrenceList,
      servicesById: servicesById,
    );

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_outlined,
                      color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conflicts.length == 1
                          ? 'Este instrutor já tem uma aula a esta hora. '
                              'Podes continuar, mas confirma que não é engano.'
                          : 'Este instrutor já tem ${conflicts.length} aulas a '
                              'esta hora. Podes continuar, mas confirma que '
                              'não é engano.',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
              if (daySchedule.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  recurring
                      ? 'O que ele já tem à ${weekdayName(dayOfWeek).toLowerCase()}:'
                      : 'O que ele já tem nesse dia:',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                for (final entry in daySchedule)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '•  $entry',
                      style: TextStyle(
                          color: scheme.onErrorContainer, fontSize: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
      error: (error, stack) => ErrorState(
        error: error,
        message: 'Não foi possível carregar membros elegíveis.',
        compact: true,
      ),
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
