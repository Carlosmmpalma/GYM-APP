import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/free_training_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firebase_error_text.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/free_training_slot.dart';
import '../../application/providers/plan_providers.dart';
import '../widgets/design_system.dart';

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
            error: (error, stack) => ErrorState(error: error),
            data: (schedule) {
              if (schedule == null || !schedule.isPublished) {
                return const EmptyState(
                  icon: Icons.self_improvement_outlined,
                  title: 'Semana ainda não publicada',
                  message: 'O treino livre funciona por blocos de horário '
                      'que o ginásio publica todas as semanas. Quando esta '
                      'semana for publicada, aparecem aqui os blocos com '
                      'as vagas disponíveis.',
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
    final eligibleAsync = ref.watch(myEligibleServiceIdsProvider);

    return slotsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorState(error: error),
      data: (allSlots) {
        // Fase 11 — o treino livre também é um serviço, e nem todos os
        // planos lhe dão acesso. Mesmo raciocínio (e mesma fonte) do
        // filtro em "Marcar treino": não mostrar portas fechadas, sem
        // deixar de contar com o servidor para as fechar.
        final eligible = eligibleAsync.valueOrNull;
        final slots = eligible == null
            ? allSlots
            : allSlots.where((s) => eligible.contains(s.serviceId)).toList();

        if (slots.isEmpty && allSlots.isNotEmpty) {
          return const EmptyState(
            icon: Icons.lock_outline,
            title: 'O teu plano não inclui treino livre',
            message: 'Há blocos publicados esta semana, mas o teu plano não '
                'dá acesso a treino livre. Fala com o estúdio se quiseres '
                'acrescentá-lo.',
          );
        }

        if (slots.isEmpty) {
          return const EmptyState(
            icon: Icons.self_improvement_outlined,
            title: 'Sem blocos nesta semana',
            message: 'A grelha desta semana está publicada mas ainda não tem '
                'nenhum bloco. Usa as setas em cima para ver outra semana.',
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

/// Um bloco de treino livre, do lado do Aluno.
///
/// Auditoria da Fase 11 — três coisas erradas aqui:
///
///  1. **Sem estado de ocupado.** O botão ficava ativo durante a
///     chamada à Cloud Function; dois toques seguidos disparavam duas
///     reservas (a segunda falhava, mas com um erro cru na cara de quem
///     só tinha tocado depressa).
///  2. **Blocos já passados ofereciam "Reservar".** Na sexta-feira, o
///     bloco de segunda às 8h continuava com o botão ativo; o servidor
///     recusava, e a recusa chegava como erro genérico.
///  3. **Erros mostrados em cru.** `'$e'` num SnackBar dá exatamente o
///     `[firebase_functions/internal] internal` que não diz nada a
///     ninguém. Passou a usar a mesma tradução do resto da app.
class _SlotTile extends ConsumerStatefulWidget {
  const _SlotTile({required this.slot, required this.memberId});

  final FreeTrainingSlot slot;
  final String memberId;

  @override
  ConsumerState<_SlotTile> createState() => _SlotTileState();
}

class _SlotTileState extends ConsumerState<_SlotTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    // Derivado das marcações que já vêm carregadas (ver
    // `myFreeTrainingSlotIdsProvider`): era uma leitura por bloco,
    // multiplicada por cada abertura do separador.
    final isBooked = ref
        .watch(myFreeTrainingSlotIdsProvider)
        .contains('${slot.weekId}/${slot.id}');
    final hasPassed = slot.startAt.isBefore(DateTime.now());

    return Card(
      child: ListTile(
        title: Text(
          '${_timeFormat.format(slot.startAt)}–${_timeFormat.format(slot.endAt)}',
          style: TextStyle(color: hasPassed ? AppColors.mute : null),
        ),
        subtitle: Text(
          hasPassed
              ? (isBooked ? 'Já passou · tinhas reservado' : 'Já passou')
              : isBooked
                  ? '${slot.availableSlots} vaga(s) restante(s) · já reservaste'
                  : '${slot.availableSlots} vaga(s) restante(s)',
        ),
        trailing: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : hasPassed
                ? null
                : FilledButton(
                    onPressed:
                        isBooked ? _cancel : (slot.isFull ? null : _book),
                    child: Text(isBooked
                        ? 'Cancelar'
                        : (slot.isFull ? 'Sem vagas' : 'Reservar')),
                  ),
      ),
    );
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _book() async {
    setState(() => _busy = true);
    try {
      await ref.read(freeTrainingRepositoryProvider).bookSlot(
            weekId: widget.slot.weekId,
            slotId: widget.slot.id,
            memberId: widget.memberId,
          );
      ref.invalidate(myBookingsProvider);
      _show('Reservado.');
    } catch (e) {
      // As exceções de domínio (`NotEligibleForServiceException`,
      // `UsageLimitReachedException`, …) já dizem o que aconteceu em
      // português; só o que vem cru do Firebase precisa de tradução.
      _show(describeFirebaseError(e) ?? '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      final usageRefunded =
          await ref.read(freeTrainingRepositoryProvider).cancelSlotBooking(
                weekId: widget.slot.weekId,
                slotId: widget.slot.id,
                memberId: widget.memberId,
              );
      ref.invalidate(myBookingsProvider);
      _show(
        usageRefunded
            ? 'Cancelado — utilização semanal devolvida.'
            : 'Cancelado — fora da janela mínima, utilização não devolvida.',
      );
    } catch (e) {
      _show(describeFirebaseError(e) ?? '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
