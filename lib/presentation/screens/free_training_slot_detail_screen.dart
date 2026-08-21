import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/free_training_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/attendance.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/free_training_slot.dart';
import '../../domain/entities/member_summary.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/design_system.dart';

final _dateFormat = DateFormat('EEE, d MMM · HH:mm', 'pt_PT');

/// Fase 7 — detalhe de um bloco de treino livre para Gestor/Instrutor:
/// lista de inscritos COM nomes (`firestore.rules` só deixa
/// Manager/Instrutor listar isto — ver nota em `firestore.rules`).
/// Presença é Manager-only (UC10-A fechado: "o Gestor, não o
/// Instrutor, que só tem leitura sobre o treino livre"); atribuição
/// manual também Manager-only, mesmo espírito de `OccurrenceDetailScreen`
/// mas sem reduzir vagas/cancelar/remarcar — não pedidos para esta
/// fase.
class FreeTrainingSlotDetailScreen extends ConsumerWidget {
  const FreeTrainingSlotDetailScreen({super.key, required this.slot});

  final FreeTrainingSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(
      freeTrainingSlotBookingsProvider((weekId: slot.weekId, slotId: slot.id)),
    );
    final membersAsync = ref.watch(membersProvider);
    final isManager =
        ref.watch(currentAppUserProvider).valueOrNull?.isManager ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Treino livre')),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _assignMembers(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Atribuir'),
            )
          : null,
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
                    _dateFormat.format(slot.startAt),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('${slot.activeBookingCount}/${slot.capacity} inscritos'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Inscritos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          bookingsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ErrorState(error: error, compact: true),
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
              final membersByUid = <String, MemberSummary>{
                for (final m
                    in membersAsync.valueOrNull ?? const <MemberSummary>[])
                  m.uid: m,
              };
              return Column(
                children: active
                    .map(
                      (booking) => _MemberTile(
                        slot: slot,
                        booking: booking,
                        member: membersByUid[booking.memberId],
                        isManager: isManager,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _assignMembers(BuildContext context, WidgetRef ref) async {
    final eligible =
        await ref.read(eligibleMembersProvider(slot.serviceId).future);
    if (!context.mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Nenhum membro tem um plano ativo que dê acesso a este serviço.'),
        ),
      );
      return;
    }

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _AssignMembersDialog(eligible: eligible),
    );
    if (selected == null || selected.isEmpty) return;

    try {
      final results =
          await ref.read(freeTrainingRepositoryProvider).assignMembers(
                weekId: slot.weekId,
                slotId: slot.id,
                memberIds: selected.toList(),
              );
      if (!context.mounted) return;
      final ok = results.values.where((v) => v).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('$ok de ${results.length} atribuído(s) com sucesso.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atribuir: $e')),
      );
    }
    ref.invalidate(eligibleMembersProvider(slot.serviceId));
  }
}

class _AssignMembersDialog extends StatefulWidget {
  const _AssignMembersDialog({required this.eligible});

  final List<MemberSummary> eligible;

  @override
  State<_AssignMembersDialog> createState() => _AssignMembersDialogState();
}

class _AssignMembersDialogState extends State<_AssignMembersDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atribuir membros'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.eligible
              .map(
                (member) => CheckboxListTile(
                  title: Text(member.name),
                  value: _selected.contains(member.uid),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _selected.add(member.uid);
                    } else {
                      _selected.remove(member.uid);
                    }
                  }),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Atribuir'),
        ),
      ],
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.slot,
    required this.booking,
    required this.member,
    required this.isManager,
  });

  final FreeTrainingSlot slot;
  final Booking booking;
  final MemberSummary? member;
  final bool isManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(
      freeTrainingSlotAttendanceProvider(
          (weekId: slot.weekId, slotId: slot.id)),
    );
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
        subtitle: Text(member == null ? '' : 'Nº ${member!.memberNumber}'),
        trailing: isManager
            ? Row(
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
                    onPressed: () =>
                        _record(context, ref, AttendanceStatus.attended),
                  ),
                  IconButton(
                    tooltip: 'Faltou',
                    icon: Icon(
                      Icons.cancel,
                      color: attendance?.status == AttendanceStatus.noShow
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).disabledColor,
                    ),
                    onPressed: () =>
                        _record(context, ref, AttendanceStatus.noShow),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _record(
      BuildContext context, WidgetRef ref, AttendanceStatus status) async {
    final recordedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (recordedBy == null) return;
    try {
      await ref.read(freeTrainingRepositoryProvider).recordAttendance(
            weekId: slot.weekId,
            slotId: slot.id,
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
