import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../widgets/design_system.dart';

/// UC10 — "Minhas marcações". Mostra as marcações ativas do próprio
/// membro e permite cancelar.
///
/// Até à Fase 5 mostrava só "Marcação #abc123" + a data em que foi
/// FEITA a marcação — nunca o nome do serviço nem a hora da SESSÃO em
/// si (a Fase 4 já lia a ocorrência associada, mas só internamente,
/// para calcular o aviso de cancelamento; nunca chegou a mostrar-se).
/// Bug real, ficou muito mais visível com várias séries possíveis
/// desde a Fase 5 — corrigido: cada cartão mostra agora o nome do
/// serviço e a data/hora da sessão.
class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorState(error: error),
      data: (bookings) {
        final active = bookings
            .where((b) => b.status == BookingStatus.booked)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (active.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Sem marcações',
            message: 'Aqui ficam as sessões que já reservaste, com a opção '
                'de cancelar. Usa o separador "Marcar" para reservares uma '
                'aula, ou "Livre" para o treino livre.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: active.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _BookingTile(
            // Ver nota em `book_training_screen.dart`: itens de lista
            // com estado precisam de key.
            key: ValueKey(active[index].id),
            booking: active[index],
          ),
        );
      },
    );
  }
}

class _BookingTile extends ConsumerStatefulWidget {
  const _BookingTile({super.key, required this.booking});

  final Booking booking;

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
  Future<bool> _confirm() async {
    final serviceId = widget.booking.serviceId;
    final SessionOccurrence? occurrence =
        await ref.read(occurrenceProvider(widget.booking.occurrenceId).future);
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
    final hoursUntilStart = occurrence == null
        ? null
        : occurrence.startAt.difference(DateTime.now()).inMinutes / 60;
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

  Future<void> _cancel() async {
    final confirmed = await _confirm();
    if (!confirmed || !mounted) return;

    setState(() {
      _isCancelling = true;
      _error = null;
    });
    try {
      final useCase = ref.read(cancelBookingUseCaseProvider);
      final usageRefunded = await useCase(
        occurrenceId: widget.booking.occurrenceId,
        memberId: widget.booking.memberId,
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
      final serviceId = widget.booking.serviceId;
      final period = widget.booking.period;
      if (serviceId != null && period != null) {
        ref.invalidate(usageProvider((
          memberId: widget.booking.memberId,
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
    final occurrenceAsync =
        ref.watch(occurrenceProvider(widget.booking.occurrenceId));
    final servicesAsync = ref.watch(servicesProvider);

    final occurrence = occurrenceAsync.valueOrNull;
    final servicesById = {
      for (final s in servicesAsync.valueOrNull ?? const []) s.id: s,
    };
    final serviceName = occurrence == null
        ? null
        : servicesById[occurrence.serviceId]?.name ?? occurrence.serviceId;

    final subtitleText = occurrenceAsync.isLoading
        ? 'A carregar…'
        : occurrence == null
            ? 'Sessão já não disponível'
            : dateFormat.format(occurrence.startAt);

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
                    Text(
                      serviceName ?? 'Marcação',
                      style: const TextStyle(fontSize: 14),
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
              if (_isCancelling)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(onPressed: _cancel, child: const Text('Cancelar')),
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
