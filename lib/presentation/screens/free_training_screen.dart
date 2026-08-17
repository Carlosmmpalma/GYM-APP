import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/free_training_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/free_training_slot.dart';

final _dayFormat = DateFormat('EEE, d MMM', 'pt_PT');
final _timeFormat = DateFormat('HH:mm', 'pt_PT');
final _weekRangeFormat = DateFormat('d MMM', 'pt_PT');

/// Fase 7 (UC09) — "Treino sem acompanhamento": o Aluno só vê a
/// CONTAGEM de vagas de cada horário, nunca quem mais está inscrito
/// (diferença de visibilidade por papel, aplicada a sério nas Security
/// Rules — ver `firestore.rules`, não só escondida aqui). Navegação
/// semana a semana (seta anterior/seguinte); uma semana sem grelha
/// publicada mostra um estado vazio explícito, nunca uma lista de
/// horários "por publicar" (a Security Rule já bloqueia essa leitura
/// para o Aluno, mas o ecrã não deve nem tentar sugerir que existe
/// algo escondido).
class FreeTrainingScreen extends ConsumerStatefulWidget {
  const FreeTrainingScreen({super.key});

  @override
  ConsumerState<FreeTrainingScreen> createState() => _FreeTrainingScreenState();
}

class _FreeTrainingScreenState extends ConsumerState<FreeTrainingScreen> {
  late DateTime _weekAnchor = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final weekId = weekIdForDate(_weekAnchor);
    final weekRange = isoWeekRange(_weekAnchor);
    final memberId = ref.watch(currentAppUserProvider).valueOrNull?.uid;
    final scheduleAsync = ref.watch(freeTrainingScheduleProvider(weekId));

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Semana anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() =>
                  _weekAnchor = _weekAnchor.subtract(const Duration(days: 7))),
            ),
            Text(
              '${_weekRangeFormat.format(weekRange.start)} – '
              '${_weekRangeFormat.format(weekRange.end)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Semana seguinte',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                  () => _weekAnchor = _weekAnchor.add(const Duration(days: 7))),
            ),
          ],
        ),
        Expanded(
          child: scheduleAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Erro: $error')),
            data: (schedule) {
              if (schedule == null || !schedule.isPublished) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Ainda não há grelha publicada para esta semana.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (memberId == null) return const SizedBox.shrink();
              return _SlotsList(weekId: weekId, memberId: memberId);
            },
          ),
        ),
      ],
    );
  }
}

class _SlotsList extends ConsumerWidget {
  const _SlotsList({required this.weekId, required this.memberId});

  final String weekId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotsAsync = ref.watch(freeTrainingSlotsProvider(weekId));

    return slotsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Erro: $error')),
      data: (slots) {
        if (slots.isEmpty) {
          return const Center(
            child: Text('Nenhum horário nesta semana.'),
          );
        }

        final byDay = <DateTime, List<FreeTrainingSlot>>{};
        for (final slot in slots) {
          final day =
              DateTime(slot.startAt.year, slot.startAt.month, slot.startAt.day);
          (byDay[day] ??= []).add(slot);
        }
        final days = byDay.keys.toList()..sort();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final day in days) ...[
              Text(_dayFormat.format(day),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final slot in byDay[day]!) ...[
                _SlotTile(slot: slot, memberId: memberId),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SlotTile extends ConsumerWidget {
  const _SlotTile({required this.slot, required this.memberId});

  final FreeTrainingSlot slot;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myBookingAsync = ref.watch(
      myFreeTrainingBookingProvider(
          (weekId: slot.weekId, slotId: slot.id, memberId: memberId)),
    );
    final isBooked = myBookingAsync.valueOrNull != null;

    return Card(
      child: ListTile(
        title: Text(
          '${_timeFormat.format(slot.startAt)}–${_timeFormat.format(slot.endAt)}',
        ),
        subtitle: Text(
          isBooked
              ? '${slot.availableSlots} vaga(s) restante(s) · já reservaste'
              : '${slot.availableSlots} vaga(s) restante(s)',
        ),
        trailing: myBookingAsync.isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton(
                onPressed: isBooked
                    ? () => _cancel(context, ref)
                    : (slot.isFull ? null : () => _book(context, ref)),
                child: Text(isBooked
                    ? 'Cancelar'
                    : (slot.isFull ? 'Sem vagas' : 'Reservar')),
              ),
      ),
    );
  }

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(freeTrainingRepositoryProvider).bookSlot(
            weekId: slot.weekId,
            slotId: slot.id,
            memberId: memberId,
          );
      ref.invalidate(myFreeTrainingBookingProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      final usageRefunded =
          await ref.read(freeTrainingRepositoryProvider).cancelSlotBooking(
                weekId: slot.weekId,
                slotId: slot.id,
                memberId: memberId,
              );
      ref.invalidate(myFreeTrainingBookingProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usageRefunded
                ? 'Cancelado — utilização semanal devolvida.'
                : 'Cancelado — fora da janela mínima, utilização não devolvida.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}
