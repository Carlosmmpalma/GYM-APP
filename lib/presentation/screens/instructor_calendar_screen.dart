import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/free_training_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/free_training_schedule.dart';
import '../../domain/entities/free_training_slot.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/staff_summary.dart';
import '../widgets/design_system.dart';
import 'free_training_slot_detail_screen.dart';
import 'occurrence_detail_screen.dart';

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

/// Fase 6 (UC20) — "calendário do instrutor". Primeira área da app
/// própria para um Instrutor — até aqui só o Gestor tinha ecrãs de
/// gestão (decisão explícita da Fase 5, ver `manage_series_screen.dart`).
/// Reaproveitado também pelo Gestor (`instructorId: null` → vê TODAS as
/// sessões, não só as de um instrutor), a partir de `ManagerScreen`
/// ("visão do gestor" nos mockups é a mesma janela, sem filtro).
///
/// Toca numa sessão → `OccurrenceDetailScreen`, o mesmo ecrã de
/// presença/reduzir vagas/remarcar/cancelar/notificar já usado pela
/// Gestão — os mockups mostram estas ações também na secção
/// "Instrutor", não é um ecrã à parte.
///
/// Fase 7 — passou a mesclar também o treino livre (UC20 atualizado:
/// "recurso partilhado, visível a qualquer instrutor"), numa secção
/// "Treino livre" do dia selecionado. Só semanas `published` entram
/// aqui — rascunho/sugestão por aprovar ficam exclusivos de
/// `ManageFreeTrainingScreen`, mesma restrição que a Security Rule já
/// aplica a um Instrutor.
///
/// Fase 8 (auditoria funcional, UC20 atualizado) — passou de "próximas
/// 2 semanas, tudo junto numa lista contínua" para o layout real do
/// mockup "Semana — visão do gestor": navegação semana a semana
/// (mesmo padrão de `ManageFreeTrainingScreen`) + tabs Seg-Dom para
/// escolher o dia.
///
/// A primeira versão desta mudança mostrava só a contagem de
/// inscritos, por recear N+1 queries. Na 2ª passagem da auditoria isso
/// foi revisto: o UC20 pede *"nº de inscritos **e lista de nomes** por
/// slot"* e as tabs por dia tornaram o custo aceitável — ver
/// [_OccurrenceSubtitle].
class InstructorCalendarScreen extends ConsumerStatefulWidget {
  const InstructorCalendarScreen({super.key, this.instructorId});

  final String? instructorId;

  @override
  ConsumerState<InstructorCalendarScreen> createState() =>
      _InstructorCalendarScreenState();
}

class _InstructorCalendarScreenState
    extends ConsumerState<InstructorCalendarScreen> {
  late DateTime _weekAnchor = DateTime.now();
  late int _selectedWeekday = DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    final weekRange = isoWeekRange(_weekAnchor);
    final weekId = weekIdForDate(_weekAnchor);
    final selectedDay =
        weekRange.start.add(Duration(days: _selectedWeekday - 1));

    final occurrencesAsync =
        ref.watch(occurrencesForWeekProvider(weekRange.start));
    final servicesAsync = ref.watch(servicesProvider);
    final modalitiesAsync = ref.watch(modalitiesProvider);
    final staffAsync = ref.watch(staffProvider);
    final scheduleAsync = ref.watch(freeTrainingScheduleProvider(weekId));
    final slotsAsync = ref.watch(freeTrainingSlotsProvider(weekId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.instructorId == null ? 'Semana' : 'As minhas aulas'),
      ),
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
          // Fase 10 — `PillTabs` em vez de sete `ChoiceChip` esticados
          // por `Expanded`: com "Seg".."Dom" a caber num ecrã de telefone
          // à justa, os chips ficavam com o texto cortado. Os pills têm
          // largura natural e a fila faz scroll horizontal.
          PillTabs(
            labels: _weekdayLabels.values.toList(),
            selectedIndex:
                _weekdayLabels.keys.toList().indexOf(_selectedWeekday),
            onSelected: (i) => setState(
              () => _selectedWeekday = _weekdayLabels.keys.elementAt(i),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: occurrencesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorState(error: error),
              data: (occurrences) {
                final servicesById = <String, Service>{
                  for (final s
                      in servicesAsync.valueOrNull ?? const <Service>[])
                    s.id: s,
                };
                final modalitiesById = <String, Modality>{
                  for (final m
                      in modalitiesAsync.valueOrNull ?? const <Modality>[])
                    m.id: m,
                };
                final staffByUid = <String, StaffSummary>{
                  for (final s
                      in staffAsync.valueOrNull ?? const <StaffSummary>[])
                    s.uid: s,
                };

                final dayOccurrences = occurrences
                    .where((o) =>
                        (widget.instructorId == null ||
                            o.instructorId == widget.instructorId) &&
                        _isSameDay(o.startAt, selectedDay))
                    .toList()
                  ..sort((a, b) => a.startAt.compareTo(b.startAt));

                final schedule = scheduleAsync.valueOrNull;
                final daySlots = schedule?.status ==
                        FreeTrainingScheduleStatus.published
                    ? ((slotsAsync.valueOrNull ?? const <FreeTrainingSlot>[])
                        .where((s) => _isSameDay(s.startAt, selectedDay))
                        .toList()
                      ..sort((a, b) => a.startAt.compareTo(b.startAt)))
                    : const <FreeTrainingSlot>[];

                if (dayOccurrences.isEmpty && daySlots.isEmpty) {
                  return const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'Dia livre',
                    message: 'Não há aulas nem blocos de treino livre neste '
                        'dia. Usa as setas em cima para mudar de semana.',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final occurrence in dayOccurrences) ...[
                      Card(
                        child: ListTile(
                          title: Text(
                            '${_timeFormat.format(occurrence.startAt)} · '
                            '${servicesById[occurrence.serviceId]?.name ?? occurrence.serviceId}',
                          ),
                          subtitle: _OccurrenceSubtitle(
                            occurrence: occurrence,
                            prefixParts: [
                              if (occurrence.modalityId != null)
                                modalitiesById[occurrence.modalityId]?.name ??
                                    '',
                              if (widget.instructorId == null &&
                                  occurrence.instructorId != null)
                                staffByUid[occurrence.instructorId]?.name ?? '',
                            ].where((p) => p.isNotEmpty).toList(),
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
                    if (daySlots.isNotEmpty) ...[
                      Text(
                        'Treino livre',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final slot in daySlots) ...[
                        Card(
                          child: ListTile(
                            title: Text(
                              '${_timeFormat.format(slot.startAt)}–${_timeFormat.format(slot.endAt)}',
                            ),
                            subtitle: Text(
                                '${slot.activeBookingCount}/${slot.capacity} inscritos'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    FreeTrainingSlotDetailScreen(slot: slot),
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
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Fase 8 (auditoria funcional, UC20) — o use case pede
/// explicitamente *"nº de inscritos **e lista de nomes** por slot"*, e
/// o mockup mostra "9/12 · Rita, Miguel, Tiago...". A primeira versão
/// do calendário (semana inteira numa lista contínua) mostrava só a
/// contagem, porque carregar os inscritos de TODAS as sessões de 2
/// semanas seria uma query por sessão sem limite nenhum.
///
/// Com as tabs por dia isso deixou de ser verdade: o ecrã mostra só as
/// sessões de UM dia (tipicamente 3-8), por isso o nº de listeners é
/// pequeno e limitado pelo próprio layout. Só os primeiros [_maxNames]
/// nomes são mostrados — o resto vira "+N", como no mockup; a lista
/// completa está a um toque de distância em `OccurrenceDetailScreen`.
class _OccurrenceSubtitle extends ConsumerWidget {
  const _OccurrenceSubtitle({
    required this.occurrence,
    required this.prefixParts,
  });

  static const _maxNames = 3;

  final SessionOccurrence occurrence;
  final List<String> prefixParts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts =
        '${occurrence.activeBookingCount}/${occurrence.capacity} inscritos';

    // Uma sessão cancelada não tem inscritos ativos para listar (a
    // cascata de `cancelOccurrenceForStudio` libertou-os todos) — evita
    // um listener por sessão cancelada sem nada para mostrar.
    if (occurrence.status == SessionOccurrenceStatus.cancelled) {
      return Text([...prefixParts, counts, 'cancelada'].join(' · '));
    }
    if (occurrence.activeBookingCount == 0) {
      return Text([...prefixParts, counts].join(' · '));
    }

    final bookingsAsync = ref.watch(occurrenceBookingsProvider(occurrence.id));
    final membersById = <String, MemberSummary>{
      for (final m
          in ref.watch(membersProvider).valueOrNull ?? const <MemberSummary>[])
        m.uid: m,
    };

    final names = (bookingsAsync.valueOrNull ?? const <Booking>[])
        .where((b) => b.status == BookingStatus.booked)
        .map((b) => membersById[b.memberId]?.name)
        .whereType<String>()
        .toList();

    final shown = names.take(_maxNames).join(', ');
    final extra = names.length - _maxNames;
    final namesPart =
        names.isEmpty ? '' : (extra > 0 ? '$shown +$extra' : shown);

    return Text(
      [...prefixParts, counts, if (namesPart.isNotEmpty) namesPart].join(' · '),
    );
  }
}
