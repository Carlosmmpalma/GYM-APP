import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';

/// UC05/06/07 — versão mínima da Fase 2 (guia-desenvolvimento.md,
/// Fase 2: "Ecrã 'Marcar treino' (versão mínima, uma sessão só)").
///
/// Não faz seleção de serviço/modalidade (só existe uma Service de
/// teste), não valida elegibilidade por plano contratado (isso é
/// Fase 3), nem antecedência mínima (Fase 6). É deliberadamente o
/// caminho mais simples possível, para validar a transação de booking
/// ponta a ponta antes de construir a UI completa.
class BookTrainingScreen extends ConsumerWidget {
  const BookTrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch (não read) o currentAppUserProvider aqui, no build principal —
    // não dentro do handler de tap de cada tile. Um StreamProvider só é
    // inicializado quando alguém o "olha" pela primeira vez; se isso só
    // acontecesse dentro de _book() via ref.read(), a primeira leitura
    // apanhava sempre o provider ainda em AsyncLoading (o Stream ainda não
    // tinha tido oportunidade de emitir), e a marcação era silenciosamente
    // ignorada (appUser == null). Watch aqui garante que já está resolvido
    // antes de qualquer botão poder ser premido.
    final appUserAsync = ref.watch(currentAppUserProvider);
    final serviceAsync = ref.watch(primaryServiceProvider);

    return appUserAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Erro: $error')),
      data: (appUser) {
        if (appUser == null) {
          return const Center(
            child: Text('Sem sessão iniciada.', textAlign: TextAlign.center),
          );
        }

        return serviceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('Erro: $error')),
          data: (service) {
            if (service == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ainda não existe nenhum serviço configurado neste tenant.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final occurrencesAsync =
                ref.watch(upcomingOccurrencesProvider(service.id));

            return occurrencesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Erro: $error')),
              data: (occurrences) {
                if (occurrences.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Sem sessões futuras para marcar.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: occurrences.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _OccurrenceTile(
                    occurrence: occurrences[index],
                    memberId: appUser.uid,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _OccurrenceTile extends ConsumerStatefulWidget {
  const _OccurrenceTile({required this.occurrence, required this.memberId});

  final SessionOccurrence occurrence;
  final String memberId;

  @override
  ConsumerState<_OccurrenceTile> createState() => _OccurrenceTileState();
}

class _OccurrenceTileState extends ConsumerState<_OccurrenceTile> {
  bool _isBooking = false;
  String? _error;

  Future<void> _book() async {
    setState(() {
      _isBooking = true;
      _error = null;
    });

    try {
      final useCase = ref.read(bookSessionUseCaseProvider);
      await useCase(
        occurrenceId: widget.occurrence.id,
        memberId: widget.memberId,
      );
      // Ver nota em my_bookings_screen.dart#_cancel: invalidar força uma
      // nova subscrição/fetch imediata em vez de esperar pela propagação
      // do listener do Firestore.
      ref.invalidate(upcomingOccurrencesProvider(widget.occurrence.serviceId));
    } on BookingCapacityExceededException catch (e) {
      setState(() => _error = e.toString());
    } on AlreadyBookedException catch (e) {
      setState(() => _error = e.toString());
    } on SessionNotBookableException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Não foi possível marcar. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = widget.occurrence;
    final dateFormat = DateFormat('EEE, d MMM · HH:mm', 'pt_PT');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateFormat.format(occurrence.startAt),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              occurrence.isFull
                  ? 'Sem vagas'
                  : '${occurrence.availableSlots} vaga(s) de ${occurrence.capacity}',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (occurrence.isBookable && !_isBooking) ? _book : null,
              child: _isBooking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(occurrence.isFull ? 'Sem vagas' : 'Marcar'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
