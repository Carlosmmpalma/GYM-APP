import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/attendance.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/staff_summary.dart';
import '../../repositories/session_occurrence_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/offline_write.dart';
import '../widgets/design_system.dart';
import '../widgets/occurrence_dialogs.dart';
import 'manage_series_screen.dart';
import 'group_workout_screen.dart';
import 'send_notification_screen.dart';

/// Fase 6 — "detalhe da aula" (mockup: inscritos + presença/UC10-A +
/// sessão extra/UC08-A + remarcar/UC10-B + editar/cancelar/UC18).
/// Até esta fase, NENHUM ecrã mostrava os nomes de quem estava
/// marcado numa ocorrência — `SeriesDetailScreen` só mostrava a
/// contagem "X/Y". Acessível a partir de `SeriesDetailScreen` e do
/// calendário do instrutor — as ações aqui (presença, reduzir vagas,
/// remarcar, cancelar, notificar) ficam disponíveis a Manager E
/// Instrutor, tal como os mockups mostram estas ações na secção
/// "Instrutor", não só "Gestor".
class OccurrenceDetailScreen extends ConsumerWidget {
  const OccurrenceDetailScreen({super.key, required this.occurrenceId});

  final String occurrenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occurrenceAsync = ref.watch(liveOccurrenceProvider(occurrenceId));
    final bookingsAsync = ref.watch(occurrenceBookingsProvider(occurrenceId));
    final membersAsync = ref.watch(membersProvider);
    final servicesAsync = ref.watch(servicesProvider);
    final modalitiesAsync = ref.watch(modalitiesProvider);
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sessão')),
      body: occurrenceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (occurrence) {
          if (occurrence == null) {
            return const Center(child: Text('Esta sessão já não existe.'));
          }
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
          final membersByUid = <String, MemberSummary>{
            for (final m in membersAsync.valueOrNull ?? const <MemberSummary>[])
              m.uid: m,
          };
          final activeBookings =
              (bookingsAsync.valueOrNull ?? const <Booking>[])
                  .where((b) => b.status == BookingStatus.booked)
                  .toList();
          final isScheduled =
              occurrence.status == SessionOccurrenceStatus.scheduled;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        servicesById[occurrence.serviceId]?.name ??
                            occurrence.serviceId,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(seriesDateFormat.format(occurrence.startAt)),
                      if (occurrence.modalityId != null)
                        Text(modalitiesById[occurrence.modalityId]?.name ?? ''),
                      if (occurrence.instructorId != null)
                        Text(staffByUid[occurrence.instructorId]?.name ?? ''),
                      const SizedBox(height: 4),
                      Text(
                        '${occurrence.activeBookingCount}/${occurrence.capacity} inscritos'
                        '${occurrence.status.name == 'cancelled' ? ' · cancelada' : ''}',
                      ),
                    ],
                  ),
                ),
              ),
              if (isScheduled) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: activeBookings.isEmpty
                            ? null
                            : () => _reduceSlots(context, ref, occurrence,
                                activeBookings, membersByUid),
                        child: const Text('Reduzir vagas'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () =>
                            _cancelSession(context, ref, activeBookings.length),
                        child: const Text('Cancelar sessão'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // O botão da aula a decorrer: registar o treino da
                // turma toda sem sair daqui. Ver `GroupWorkoutScreen`
                // — abrir a ficha de cada aluno, um a um, era
                // impossível de fazer a dar uma aula.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: activeBookings.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupWorkoutScreen(
                                  occurrenceId: occurrence.id,
                                  title: servicesById[occurrence.serviceId]
                                          ?.name ??
                                      'Aula',
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Treinar com a turma'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: activeBookings.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SendNotificationScreen(
                                  occurrenceId: occurrence.id),
                            ),
                          ),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Notificar inscritos'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _editOccurrence(context, ref, occurrence),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar aula'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: occurrence.availableSlots <= 0
                            ? null
                            : () => _assignMember(context, ref, occurrence,
                                isExtra: false),
                        icon: const Icon(Icons.person_add_alt_outlined),
                        label: const Text('Adicionar membro'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: occurrence.availableSlots <= 0
                      ? null
                      : () => _assignMember(context, ref, occurrence,
                          isExtra: true),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('+ Sessão extra'),
                ),
              ],
              const SizedBox(height: 24),
              Text('Inscritos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              bookingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    ErrorState(error: error, compact: true),
                data: (bookings) {
                  final active = bookings
                      .where((b) => b.status == BookingStatus.booked)
                      .toList();
                  if (active.isEmpty) {
                    return const Text(
                      'Ainda não há ninguém inscrito.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    );
                  }
                  return Column(
                    children: [
                      _BulkAttendance(
                        occurrenceId: occurrence.id,
                        memberIds: active.map((b) => b.memberId).toList(),
                      ),
                      ...active.map(
                        (booking) => _MemberTile(
                          occurrence: occurrence,
                          booking: booking,
                          member: membersByUid[booking.memberId],
                          modalitiesById: modalitiesById,
                          staffByUid: staffByUid,
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Fase 11 — a fila de quem quer entrar se alguém
              // cancelar. Aparece só quando existe: numa sessão com
              // vagas seria um título vazio em todos os ecrãs.
              _WaitlistSection(
                occurrenceId: occurrenceId,
                membersByUid: membersByUid,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reduceSlots(
    BuildContext context,
    WidgetRef ref,
    SessionOccurrence occurrence,
    List<Booking> activeBookings,
    Map<String, MemberSummary> membersByUid,
  ) async {
    final result =
        await showDialog<({int newCapacity, List<String> memberIds})>(
      context: context,
      builder: (_) => _ReduceSlotsDialog(
        currentCapacity: occurrence.capacity,
        activeBookings: activeBookings,
        membersByUid: membersByUid,
      ),
    );
    if (result == null) return;

    try {
      await ref.read(sessionOccurrenceRepositoryProvider).removeMembers(
            occurrenceId: occurrenceId,
            memberIds: result.memberIds,
            newCapacity: result.newCapacity,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${result.memberIds.length} membro(s) removido(s), vaga reduzida.'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível reduzir vagas. Tenta outra vez.'))),
      );
    }
  }

  Future<void> _cancelSession(
      BuildContext context, WidgetRef ref, int affectedCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar esta sessão?'),
        content: Text(
          affectedCount > 0
              ? '$affectedCount inscrito(s) serão cancelados e recuperam a '
                  'utilização semanal desta sessão.'
              : 'Não há ninguém inscrito nesta sessão.',
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
            child: const Text('Cancelar sessão'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(sessionOccurrenceRepositoryProvider)
          .cancelOccurrence(occurrenceId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão cancelada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível cancelar. Tenta outra vez.'))),
      );
    }
  }

  Future<void> _editOccurrence(
    BuildContext context,
    WidgetRef ref,
    SessionOccurrence occurrence,
  ) async {
    final result = await showEditOccurrenceDialog(
      context: context,
      occurrence: occurrence,
      title: 'Editar aula',
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
            modalityId: occurrence.modalityId,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aula atualizada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível editar. Tenta outra vez.'))),
      );
    }
  }

  /// UC08-A — [isExtra] só muda o texto mostrado e o parâmetro passado
  /// à Cloud Function; a decisão de negócio em si (isentar do limite
  /// semanal, nunca da capacidade da sala) é sempre do backend.
  Future<void> _assignMember(
    BuildContext context,
    WidgetRef ref,
    SessionOccurrence occurrence, {
    required bool isExtra,
  }) async {
    final memberIds = await showAssignMemberDialog(
      context: context,
      serviceId: occurrence.serviceId,
      occurrence: occurrence,
      isExtra: isExtra,
    );
    if (memberIds == null || memberIds.isEmpty) return;

    try {
      final results =
          await ref.read(sessionOccurrenceRepositoryProvider).assignMembers(
                occurrenceId: occurrence.id,
                memberIds: memberIds,
                isExtra: isExtra,
              );
      final assigned = results.values.where((ok) => ok).length;
      final failed = results.length - assigned;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? '$assigned membro(s) atribuído(s)'
                    '${isExtra ? ' (sessão extra)' : ''}.'
                : '$assigned atribuído(s), $failed não foi possível (sem vaga ou sem plano ativo).',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível atribuir. Tenta outra vez.'))),
      );
    }
  }
}

class _ReduceSlotsDialog extends StatefulWidget {
  const _ReduceSlotsDialog({
    required this.currentCapacity,
    required this.activeBookings,
    required this.membersByUid,
  });

  final int currentCapacity;
  final List<Booking> activeBookings;
  final Map<String, MemberSummary> membersByUid;

  @override
  State<_ReduceSlotsDialog> createState() => _ReduceSlotsDialogState();
}

class _ReduceSlotsDialogState extends State<_ReduceSlotsDialog> {
  late final _capacityController =
      TextEditingController(text: widget.currentCapacity.toString());
  final Set<String> _toRemove = {};

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  int get _newCapacity =>
      int.tryParse(_capacityController.text.trim()) ?? widget.currentCapacity;

  int get _requiredRemovals => (widget.activeBookings.length - _newCapacity)
      .clamp(0, widget.activeBookings.length);

  @override
  Widget build(BuildContext context) {
    final required = _requiredRemovals;
    return AlertDialog(
      title: const Text('Reduzir vagas'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _capacityController,
                decoration: const InputDecoration(labelText: 'Nova capacidade'),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _toRemove.clear()),
              ),
              const SizedBox(height: 12),
              if (required == 0)
                const Text(
                  'A nova capacidade não obriga a remover ninguém — usa "Editar '
                  'esta ocorrência" em vez disto.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                )
              else ...[
                Text('Escolhe exatamente $required de quem sai:'),
                for (final booking in widget.activeBookings)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.membersByUid[booking.memberId]?.name ??
                          booking.memberId,
                    ),
                    value: _toRemove.contains(booking.memberId),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        if (_toRemove.length >= required) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Só podes escolher $required.')),
                          );
                          return;
                        }
                        _toRemove.add(booking.memberId);
                      } else {
                        _toRemove.remove(booking.memberId);
                      }
                    }),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: required > 0 && _toRemove.length == required
              ? () => Navigator.of(context).pop(
                  (newCapacity: _newCapacity, memberIds: _toRemove.toList()))
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// Marcar a turma inteira de uma vez.
///
/// Registar presença é o que alimenta o painel de retenção — sem
/// presenças registadas, o painel mostra toda a gente "em risco" e a
/// taxa de faltas a "—". Só que registá-las era um toque por pessoa:
/// numa aula de vinte, vinte toques, todos os dias. Ninguém faz isso
/// mais do que uma semana.
///
/// O botão só marca quem ainda NÃO tem registo. O caso normal do
/// instrutor é "vieram todos menos aqueles dois" — marca os dois que
/// faltaram e carrega aqui para o resto; sobrescrever o que ele acabou
/// de marcar seria apagar-lhe o trabalho.
class _BulkAttendance extends ConsumerStatefulWidget {
  const _BulkAttendance({required this.occurrenceId, required this.memberIds});

  final String occurrenceId;
  final List<String> memberIds;

  @override
  ConsumerState<_BulkAttendance> createState() => _BulkAttendanceState();
}

class _BulkAttendanceState extends ConsumerState<_BulkAttendance> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final recorded = (ref
                .watch(occurrenceAttendanceProvider(widget.occurrenceId))
                .valueOrNull ??
            const <Attendance>[])
        .map((a) => a.memberId)
        .toSet();
    final pending =
        widget.memberIds.where((id) => !recorded.contains(id)).toList();

    if (pending.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 15, color: AppColors.ok),
            SizedBox(width: 6),
            Text(
              'Presenças registadas para todos.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _markAll(pending),
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.done_all, size: 18),
          label: Text(
            pending.length == widget.memberIds.length
                ? 'Marcar todos como presentes'
                : 'Marcar os restantes ${pending.length} como presentes',
          ),
        ),
      ),
    );
  }

  Future<void> _markAll(List<String> pending) async {
    // `await ... .future`: um StreamProvider só arranca quando alguém
    // olha para ele, e este ecrã não o observa. Com `valueOrNull`, a
    // primeira vez que se carregava no botão apanhava-o ainda em
    // carregamento e não acontecia nada — o mesmo engano já
    // documentado em `book_training_screen.dart`.
    final recordedBy = (await ref.read(currentAppUserProvider.future))?.uid;
    if (recordedBy == null) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(attendanceRepositoryProvider);
      // Em paralelo e com desistência ao fim de alguns segundos: são
      // escritas independentes, e no ginásio a ligação cai. Ver
      // `writeOrQueue` — sem isto, marcar vinte presenças com má rede
      // deixava o botão a rodar para sempre.
      final outcome = await writeOrQueue(
        Future.wait([
          for (final memberId in pending)
            repository.recordAttendance(
              occurrenceId: widget.occurrenceId,
              memberId: memberId,
              status: AttendanceStatus.attended,
              recordedBy: recordedBy,
            ),
        ]),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(writeOutcomeMessage(
            outcome,
            confirmed: '${pending.length} presença(s) registada(s).',
          )),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível registar. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// UC10-A — presença/falta por inscrito, separada do booking (Domain
/// Model v1 §29). `attended`/`noShow` são mutuamente exclusivos e
/// substituem-se (mesmo id-por-membro do documento, `set()` sobrescreve).
class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.occurrence,
    required this.booking,
    required this.member,
    required this.modalitiesById,
    required this.staffByUid,
  });

  final SessionOccurrence occurrence;
  final Booking booking;
  final MemberSummary? member;
  // `modalitiesById`/`staffByUid` são usados pelo picker de remarcação
  // (UC10-B), para descrever as sessões de destino. `servicesById`
  // também era passado a cada tile mas nunca lido — removido na
  // revisão da Fase 8.
  final Map<String, Modality> modalitiesById;
  final Map<String, StaffSummary> staffByUid;

  String get occurrenceId => occurrence.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync =
        ref.watch(occurrenceAttendanceProvider(occurrenceId));
    Attendance? attendance;
    for (final a in attendanceAsync.valueOrNull ?? const <Attendance>[]) {
      if (a.memberId == booking.memberId) {
        attendance = a;
        break;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(member?.name ?? booking.memberId),
        subtitle: Text(
          member == null
              ? ''
              : 'Nº ${member!.memberNumber}'
                  '${booking.source.name != 'self' ? ' · atribuído' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Presente',
              icon: Icon(
                Icons.check_circle,
                color: attendance?.status == AttendanceStatus.attended
                    ? AppColors.ok
                    : Theme.of(context).disabledColor,
              ),
              onPressed: () => _record(context, ref, AttendanceStatus.attended),
            ),
            IconButton(
              tooltip: 'Faltou',
              icon: Icon(
                Icons.cancel,
                color: attendance?.status == AttendanceStatus.noShow
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).disabledColor,
              ),
              onPressed: () => _record(context, ref, AttendanceStatus.noShow),
            ),
            if (occurrence.status == SessionOccurrenceStatus.scheduled)
              IconButton(
                tooltip: 'Remarcar',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => _reschedule(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final allUpcoming =
        ref.read(allUpcomingOccurrencesProvider).valueOrNull ?? const [];
    final candidates = allUpcoming
        .where((o) =>
            o.id != occurrence.id &&
            o.serviceId == occurrence.serviceId &&
            o.status == SessionOccurrenceStatus.scheduled)
        .toList();

    final destination = await showDialog<SessionOccurrence>(
      context: context,
      builder: (_) => _RescheduleDialog(
        candidates: candidates,
        modalitiesById: modalitiesById,
        staffByUid: staffByUid,
      ),
    );
    if (destination == null) return;

    try {
      await ref.read(sessionOccurrenceRepositoryProvider).rescheduleBooking(
            fromOccurrenceId: occurrence.id,
            toOccurrenceId: destination.id,
            memberId: booking.memberId,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${member?.name ?? booking.memberId} remarcado(a).')),
      );
    } on RescheduleFailedException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível remarcar. Tenta outra vez.')),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível remarcar. Tenta outra vez.'))),
      );
    }
  }

  Future<void> _record(
      BuildContext context, WidgetRef ref, AttendanceStatus status) async {
    // Ver a nota em `_BulkAttendanceState._markAll`.
    final recordedBy = (await ref.read(currentAppUserProvider.future))?.uid;
    if (recordedBy == null) return;
    try {
      // A marca no ecrã muda logo (vem da cache local do Firestore); o
      // que isto evita é ficar à espera de uma confirmação que, sem
      // rede, não chega — ver `writeOrQueue`.
      final outcome = await writeOrQueue(
        ref.read(attendanceRepositoryProvider).recordAttendance(
              occurrenceId: occurrenceId,
              memberId: booking.memberId,
              status: status,
              recordedBy: recordedBy,
            ),
      );
      if (outcome == WriteOutcome.queued && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(writeOutcomeMessage(outcome, confirmed: ''))),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível registar presença. Tenta outra vez.'))),
      );
    }
  }
}

/// UC10-B — escolher a ocorrência de destino: só sessões futuras do
/// MESMO serviço (a elegibilidade do membro é sempre relativa ao
/// serviço, não faz sentido remarcar para um serviço diferente).
class _RescheduleDialog extends StatelessWidget {
  const _RescheduleDialog({
    required this.candidates,
    required this.modalitiesById,
    required this.staffByUid,
  });

  final List<SessionOccurrence> candidates;
  final Map<String, Modality> modalitiesById;
  final Map<String, StaffSummary> staffByUid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remarcar para...'),
      content: SizedBox(
        width: double.maxFinite,
        child: candidates.isEmpty
            ? const Text(
                'Não há outras sessões futuras deste serviço para remarcar.',
                style: TextStyle(fontStyle: FontStyle.italic),
              )
            : ListView(
                shrinkWrap: true,
                children: candidates.map((o) {
                  final parts = [
                    seriesDateFormat.format(o.startAt),
                    if (o.modalityId != null)
                      modalitiesById[o.modalityId]?.name ?? '',
                    if (o.instructorId != null)
                      staffByUid[o.instructorId]?.name ?? '',
                    '${o.activeBookingCount}/${o.capacity}',
                  ].where((p) => p.isNotEmpty).join(' · ');
                  return ListTile(
                    title: Text(parts),
                    onTap: () => Navigator.of(context).pop(o),
                  );
                }).toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

/// Fase 11 — a lista de espera vista pelo estúdio.
///
/// O aluno vê apenas a sua posição (as Rules não lhe deixam listar a
/// fila); aqui vêem-se os nomes, que é o que permite a conversa "posso
/// abrir mais uma vaga?" com dados à frente em vez de de memória.
class _WaitlistSection extends ConsumerWidget {
  const _WaitlistSection({
    required this.occurrenceId,
    required this.membersByUid,
  });

  final String occurrenceId;
  final Map<String, MemberSummary> membersByUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(occurrenceWaitlistProvider(occurrenceId));
    final queue = queueAsync.valueOrNull ?? const [];
    if (queue.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Lista de espera (${queue.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Se alguém cancelar, o primeiro da fila fica com o lugar '
          'automaticamente e é notificado.',
          style: TextStyle(color: AppColors.mute, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...queue.asMap().entries.map(
              (indexed) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: PanelCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      // A posição vem escrita pelo servidor; o índice só
                      // serve no instante entre entrar na fila e a
                      // numeração chegar.
                      Pill('${indexed.value.position ?? indexed.key + 1}º'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          membersByUid[indexed.value.memberId]?.name ??
                              indexed.value.memberId,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
