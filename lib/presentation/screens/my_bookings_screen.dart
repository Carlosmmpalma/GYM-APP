import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/free_training_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../widgets/design_system.dart';

/// UC10 — "Minhas marcações". Mostra as marcações do próprio membro e
/// permite cancelar as que ainda estão para acontecer.
///
/// Até à Fase 5 mostrava só "Marcação #abc123" + a data em que foi
/// FEITA a marcação — nunca o nome do serviço nem a hora da SESSÃO em
/// si. Corrigido nessa altura; a auditoria da Fase 11 encontrou aqui
/// mais três coisas, todas com a mesma raiz — a marcação não guardava
/// a data da sessão:
///
///  1. **Ordenava pela data em que a marcação foi feita.** Marcar hoje
///     uma aula do mês que vem punha-a no fim da lista, atrás da de
///     amanhã marcada na semana passada.
///  2. **As sessões passadas nunca saíam.** Uma marcação de há três
///     meses ficava lá com um botão "Cancelar" que não fazia sentido
///     nenhum.
///  3. **O treino livre aparecia partido.** A collection group query
///     apanha os dois tipos de marcação (aulas e treino livre vivem em
///     caminhos diferentes), e o ecrã tratava tudo como aula: os
///     cartões de treino livre diziam "Sessão já não disponível" e o
///     "Cancelar" chamava a Cloud Function errada, falhando sempre.
class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorState(error: error),
      data: (bookings) {
        final now = DateTime.now();
        final active =
            bookings.where((b) => b.status == BookingStatus.booked).toList();

        if (active.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Sem marcações',
            message: 'Aqui ficam as sessões que já reservaste, com a opção '
                'de cancelar. Usa o separador "Marcar" para reservares uma '
                'aula, ou "Livre" para o treino livre.',
          );
        }

        // Marcações antigas não têm `startAt` (o campo é da Fase 11) —
        // essas ficam sempre no grupo das próximas, porque não há como
        // saber se já passaram sem ler a ocorrência. O cartão trata
        // desse caso lendo-a, como fazia antes.
        final upcoming = active.where((b) => !b.hasPassed(now)).toList()
          ..sort(_byStartThenCreated);
        final past = active.where((b) => b.hasPassed(now)).toList()
          ..sort((a, b) => _byStartThenCreated(b, a));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (upcoming.isEmpty)
              const PanelCard(
                child: Text(
                  'Não tens nenhuma sessão futura marcada.',
                  style: TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ),
            for (final booking in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _BookingTile(
                  // Ver nota em `book_training_screen.dart`: itens de
                  // lista com estado precisam de key.
                  key: ValueKey(booking.id + booking.occurrenceId),
                  booking: booking,
                  isPast: false,
                ),
              ),
            if (past.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionLabel('Já realizadas'),
              const SizedBox(height: 8),
              // Sem botão de cancelar: cancelar uma sessão que já
              // aconteceu não devolve vaga nenhuma nem utilização, e a
              // Cloud Function recusaria de qualquer forma.
              for (final booking in past.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BookingTile(
                    key: ValueKey(booking.id + booking.occurrenceId),
                    booking: booking,
                    isPast: true,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

int _byStartThenCreated(Booking a, Booking b) {
  final aStart = a.startAt;
  final bStart = b.startAt;
  if (aStart != null && bStart != null) return aStart.compareTo(bStart);
  if (aStart != null) return -1;
  if (bStart != null) return 1;
  return a.createdAt.compareTo(b.createdAt);
}

class _BookingTile extends ConsumerStatefulWidget {
  const _BookingTile({super.key, required this.booking, required this.isPast});

  final Booking booking;
  final bool isPast;

  @override
  ConsumerState<_BookingTile> createState() => _BookingTileState();
}

class _BookingTileState extends ConsumerState<_BookingTile> {
  bool _isCancelling = false;
  String? _error;

  /// Fase 4 — pedido do Carlos: antes de cancelar, avisar se a
  /// utilização semanal vai ou não ser devolvida, em vez de cancelar
  /// silenciosamente. Isto é uma PREVISÃO calculada no cliente (a
  /// autoridade continua a ser `cancelBooking.ts`, que devolve o
  /// resultado REAL depois — ver `_cancel()`); por isso, quando algum
  /// dado ainda não carregou, assume o cenário mais simples/otimista
  /// (devolve utilização) em vez de alarmar com informação que pode
  /// estar errada.
  Future<bool> _confirm(DateTime? startAt) async {
    final serviceId = widget.booking.serviceId;
    final minNoticeHours =
        await ref.read(minCancellationNoticeHoursProvider.future);
    final rule = serviceId == null
        ? null
        : await ref.read(
            applicableUsageRuleProvider(
              (memberId: widget.booking.memberId, serviceId: serviceId),
            ).future,
          );

    final ruleIsLimited = rule != null && !rule.isUnlimited;
    final hoursUntilStart = startAt == null
        ? null
        : startAt.difference(DateTime.now()).inMinutes / 60;
    final withinWindow = minNoticeHours <= 0 ||
        hoursUntilStart == null ||
        hoursUntilStart >= minNoticeHours;

    if (!mounted) return false;

    String message;
    if (!ruleIsLimited) {
      message = 'A vaga fica livre para outro membro.';
    } else if (withinWindow) {
      message = 'A vaga fica livre para outro membro, e a utilização desta '
          'semana é devolvida.';
    } else {
      final hoursLabel = hoursUntilStart.floor().clamp(0, 999999);
      message = 'Estás a cancelar com menos de ${minNoticeHours}h de '
          'antecedência (a sessão é já daqui a ${hoursLabel}h). A vaga fica '
          'livre, mas esta marcação continua a contar para o teu limite '
          'semanal — a utilização NÃO é devolvida.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar marcação?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Manter marcação'),
          ),
          FilledButton(
            style: (ruleIsLimited && !withinWindow)
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancelar marcação'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _cancel(DateTime? startAt) async {
    final confirmed = await _confirm(startAt);
    if (!confirmed || !mounted) return;

    setState(() {
      _isCancelling = true;
      _error = null;
    });
    try {
      final booking = widget.booking;
      // Cada tipo de marcação cancela-se pela sua Cloud Function. Era
      // aqui que o treino livre falhava: ia sempre pela das aulas.
      final usageRefunded = booking.kind == BookingKind.freeTraining
          ? await ref.read(freeTrainingRepositoryProvider).cancelSlotBooking(
                weekId: booking.weekId!,
                slotId: booking.occurrenceId,
                memberId: booking.memberId,
              )
          : await ref.read(cancelBookingUseCaseProvider)(
              occurrenceId: booking.occurrenceId,
              memberId: booking.memberId,
            );
      // Invalida em vez de confiar só no listener do Firestore
      // reemitir sozinho: garante refresco imediato da lista assim que
      // o cancelamento é confirmado, sem esperar pela propagação do
      // snapshot (que contra o emulador real é quase instantânea, mas
      // não convém depender disso silenciosamente).
      ref.invalidate(myBookingsProvider);
      // Fase 4: se o cancelamento devolveu utilização (dentro da janela
      // de antecedência mínima — ver cancelBooking.ts), a barra "X/Y
      // sessões esta semana" no ecrã de marcação também precisa de
      // refrescar. `serviceId`/`period` só existem em bookings desta
      // fase em diante — ver nota em `booking.dart`.
      final serviceId = booking.serviceId;
      final period = booking.period;
      if (serviceId != null && period != null) {
        ref.invalidate(usageProvider((
          memberId: booking.memberId,
          serviceId: serviceId,
          period: period,
        )));
      }
      if (!mounted) return;
      // Mensagem final PRECISA (não a previsão do diálogo) — vem
      // diretamente do que a Cloud Function realmente fez.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usageRefunded
                ? 'Marcação cancelada — a utilização desta semana foi devolvida.'
                : 'Marcação cancelada. Esta marcação continua a contar para o '
                    'teu limite semanal.',
          ),
        ),
      );
    } on BookingNotFoundException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Não foi possível cancelar. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, d MMM · HH:mm', 'pt_PT');
    final booking = widget.booking;
    final isFreeTraining = booking.kind == BookingKind.freeTraining;

    // A data vem da própria marcação. Só quando falta (marcações
    // anteriores à Fase 11) é que se vai ler a ocorrência — e só nesse
    // caso se paga a leitura extra.
    final needsOccurrence = booking.startAt == null && !isFreeTraining;
    final occurrenceAsync = needsOccurrence
        ? ref.watch(occurrenceProvider(booking.occurrenceId))
        : const AsyncValue<SessionOccurrence?>.data(null);
    final startAt = booking.startAt ?? occurrenceAsync.valueOrNull?.startAt;

    final servicesById = {
      for (final s in ref.watch(servicesProvider).valueOrNull ?? const [])
        s.id: s,
    };
    final serviceId =
        booking.serviceId ?? occurrenceAsync.valueOrNull?.serviceId;
    final title = isFreeTraining
        ? 'Treino livre'
        : (serviceId == null ? 'Marcação' : servicesById[serviceId]?.name) ??
            'Marcação';

    final subtitleText = startAt != null
        ? dateFormat.format(startAt)
        : occurrenceAsync.isLoading
            ? 'A carregar…'
            : 'Sessão já não disponível';

    return PanelCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (isFreeTraining) ...[
                          const SizedBox(width: 6),
                          const Pill('Livre'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style:
                          const TextStyle(color: AppColors.mute, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isPast)
                const Pill('Realizada', tone: PillTone.neutral)
              else if (_isCancelling)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: () => _cancel(startAt),
                  child: const Text('Cancelar'),
                ),
            ],
          ),
          // O erro do cancelamento era a segunda linha do subtítulo, no
          // mesmo cinzento do resto — lia-se como informação normal.
          if (_error != null) ...[
            const SizedBox(height: 8),
            AppBanner(text: _error!, tone: PillTone.danger),
          ],
        ],
      ),
    );
  }
}
