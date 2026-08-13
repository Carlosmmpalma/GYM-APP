import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../domain/entities/booking.dart';

/// UC10 — "Minhas marcações" (versão mínima da Fase 2). Mostra as
/// marcações ativas do próprio membro e permite cancelar.
///
/// Não mostra ainda o nome/horário da sessão associada (isso exigiria
/// juntar dados de `sessionOccurrences`, que não está a ser feito aqui
/// de propósito — Fase 2 só prova a transação; enriquecer a UI fica
/// para a próxima iteração).
class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Erro: $error')),
      data: (bookings) {
        final active =
            bookings.where((b) => b.status == BookingStatus.booked).toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (active.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Ainda não tens nenhuma marcação.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: active.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _BookingTile(booking: active[index]),
        );
      },
    );
  }
}

class _BookingTile extends ConsumerStatefulWidget {
  const _BookingTile({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_BookingTile> createState() => _BookingTileState();
}

class _BookingTileState extends ConsumerState<_BookingTile> {
  bool _isCancelling = false;
  String? _error;

  Future<void> _cancel() async {
    setState(() {
      _isCancelling = true;
      _error = null;
    });
    try {
      final useCase = ref.read(cancelBookingUseCaseProvider);
      await useCase(
        occurrenceId: widget.booking.occurrenceId,
        memberId: widget.booking.memberId,
      );
      // Invalida em vez de confiar só no listener do Firestore
      // reemitir sozinho: garante refresco imediato da lista assim que
      // o cancelamento é confirmado, sem esperar pela propagação do
      // snapshot (que contra o emulador real é quase instantânea, mas
      // não convém depender disso silenciosamente).
      ref.invalidate(myBookingsProvider);
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
    final dateFormat = DateFormat('d MMM HH:mm', 'pt_PT');
    return Card(
      child: ListTile(
        title: Text('Marcação #${widget.booking.id.substring(0, 6)}'),
        subtitle: Text('Feita em ${dateFormat.format(widget.booking.createdAt)}'
            '${_error != null ? '\n$_error' : ''}'),
        isThreeLine: _error != null,
        trailing: _isCancelling
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(onPressed: _cancel, child: const Text('Cancelar')),
      ),
    );
  }
}
