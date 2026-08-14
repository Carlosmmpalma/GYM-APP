import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'manage_series_screen.dart';
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
        error: (error, stack) => Center(child: Text('Erro: $error')),
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
              ],
              const SizedBox(height: 24),
              Text('Inscritos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              bookingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Erro: $error'),
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
                    children: active
                        .map(
                          (booking) => _MemberTile(
                            occurrence: occurrence,
                            booking: booking,
                            member: membersByUid[booking.memberId],
                            servicesById: servicesById,
                            modalitiesById: modalitiesById,
                            staffByUid: staffByUid,
                          ),
                        )
                        .toList(),
                  );
                },
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
        SnackBar(content: Text('Não foi possível reduzir vagas: $e')),
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
        SnackBar(content: Text('Não foi possível cancelar: $e')),
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

/// UC10-A — presença/falta por inscrito, separada do booking (Domain
/// Model v1 §29). `attended`/`noShow` são mutuamente exclusivos e
/// substituem-se (mesmo id-por-membro do documento, `set()` sobrescreve).
class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.occurrence,
    required this.booking,
    required this.member,
    required this.servicesById,
    required this.modalitiesById,
    required this.staffByUid,
  });

  final SessionOccurrence occurrence;
  final Booking booking;
  final MemberSummary? member;
  final Map<String, Service> servicesById;
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
                    ? Colors.green
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
        SnackBar(content: Text('$e'), duration: const Duration(seconds: 8)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível remarcar: $e')),
      );
    }
  }

  Future<void> _record(
      BuildContext context, WidgetRef ref, AttendanceStatus status) async {
    final recordedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (recordedBy == null) return;
    try {
      await ref.read(attendanceRepositoryProvider).recordAttendance(
            occurrenceId: occurrenceId,
            memberId: booking.memberId,
            status: status,
            recordedBy: recordedBy,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível registar presença: $e')),
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
