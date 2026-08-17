import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/subscription.dart';

/// UC05/06/07 — "Marcar treino". Até à Fase 5 mostrava só as
/// ocorrências de UM serviço ("o primeiro ativo" — `primaryServiceProvider`,
/// hack da Fase 2 para não hardcodar um id); com várias séries a
/// poderem existir em serviços diferentes, isso escondia sessões reais
/// sem nenhum aviso ao aluno (bug real, reportado depois da Fase 5).
/// Mostra agora as ocorrências de TODOS os serviços
/// (`allUpcomingOccurrencesProvider`), com o nome do serviço (e do
/// instrutor, quando definido) em cada cartão — sem isso não dava para
/// perceber "que treino se trata" só pela hora/vagas.
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
    final occurrencesAsync = ref.watch(allUpcomingOccurrencesProvider);
    final servicesAsync = ref.watch(servicesProvider);
    final staffAsync = ref.watch(staffProvider);

    return appUserAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Erro: $error')),
      data: (appUser) {
        if (appUser == null) {
          return const Center(
            child: Text('Sem sessão iniciada.', textAlign: TextAlign.center),
          );
        }

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
            final servicesById = {
              for (final s in servicesAsync.valueOrNull ?? const []) s.id: s,
            };
            final staffByUid = {
              for (final s in staffAsync.valueOrNull ?? const []) s.uid: s,
            };
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: occurrences.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final occurrence = occurrences[index];
                return _OccurrenceTile(
                  occurrence: occurrence,
                  memberId: appUser.uid,
                  serviceName: servicesById[occurrence.serviceId]?.name ??
                      occurrence.serviceId,
                  instructorName: occurrence.instructorId == null
                      ? null
                      : staffByUid[occurrence.instructorId]?.name,
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
  const _OccurrenceTile({
    required this.occurrence,
    required this.memberId,
    required this.serviceName,
    required this.instructorName,
  });

  final SessionOccurrence occurrence;
  final String memberId;
  final String serviceName;
  final String? instructorName;

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
        serviceId: widget.occurrence.serviceId,
        memberId: widget.memberId,
      );
      // Ver nota em my_bookings_screen.dart#_cancel: invalidar força uma
      // nova subscrição/fetch imediata em vez de esperar pela propagação
      // do listener do Firestore. Fase 4: o mesmo vale para a barra de
      // utilização — sem isto, "X/Y" só atualizava depois do próximo
      // evento de snapshot chegar sozinho.
      ref.invalidate(allUpcomingOccurrencesProvider);
      ref.invalidate(usageProvider((
        memberId: widget.memberId,
        serviceId: widget.occurrence.serviceId,
        period: isoWeekKey(DateTime.now()),
      )));
    } on NotEligibleForServiceException catch (e) {
      setState(() => _error = e.toString());
    } on BookingCapacityExceededException catch (e) {
      setState(() => _error = e.toString());
    } on AlreadyBookedException catch (e) {
      setState(() => _error = e.toString());
    } on SessionNotBookableException catch (e) {
      setState(() => _error = e.toString());
    } on UsageLimitReachedException catch (e) {
      setState(() => _error = e.toString());
    } on TooCloseToStartException catch (e) {
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
              widget.serviceName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              dateFormat.format(occurrence.startAt) +
                  (widget.instructorName != null
                      ? ' · ${widget.instructorName}'
                      : ''),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              occurrence.isFull
                  ? 'Sem vagas'
                  : '${occurrence.availableSlots} vaga(s) de ${occurrence.capacity}',
            ),
            _WeeklyUsageLine(
              memberId: widget.memberId,
              serviceId: occurrence.serviceId,
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

/// Fase 4 story 7 — "barra '1/2 sessões esta semana'". Até à Fase 5
/// era uma única barra fixa no topo do ecrã, para o único serviço
/// visível. Com várias sessões de serviços diferentes na mesma lista,
/// isso deixou de fazer sentido — passou a ser uma linha por cartão,
/// scoped ao serviço DESSA ocorrência. Só aparece quando a [UsageRule]
/// aplicável é `limited`; para `unlimited` (ou membro sem plano —
/// caso já coberto pela mensagem de elegibilidade ao tentar marcar)
/// não mostra nada.
class _WeeklyUsageLine extends ConsumerWidget {
  const _WeeklyUsageLine({required this.memberId, required this.serviceId});

  final String memberId;
  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruleAsync = ref.watch(
      applicableUsageRuleProvider((memberId: memberId, serviceId: serviceId)),
    );

    return ruleAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (rule) {
        if (rule == null || rule.isUnlimited) return const SizedBox.shrink();
        final limit = rule.limit!;
        final period = isoWeekKey(DateTime.now());
        final usageAsync = ref.watch(
          usageProvider(
              (memberId: memberId, serviceId: serviceId, period: period)),
        );
        final used = usageAsync.valueOrNull?.used ?? 0;
        final reached = used >= limit;

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(
                reached ? Icons.block_outlined : Icons.timelapse_outlined,
                size: 16,
                color: reached ? Theme.of(context).colorScheme.error : null,
              ),
              const SizedBox(width: 6),
              Text(
                'Esta semana: $used/$limit',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
