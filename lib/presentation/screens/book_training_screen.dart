import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/subscription.dart';

/// UC05/06/07 — versão mínima da Fase 2 (guia-desenvolvimento.md,
/// Fase 2: "Ecrã 'Marcar treino' (versão mínima, uma sessão só)"),
/// com a validação de elegibilidade da Fase 3 (UC06/07/08/09: só quem
/// tem um plano ativo com acesso a este serviço pode marcar) e a barra
/// de utilização semanal da Fase 4 (story 7: "1/2 sessões esta
/// semana").
///
/// Não faz seleção de serviço/modalidade (só existe uma Service de
/// teste), nem antecedência mínima na hora de MARCAR (isso só é
/// relevante para CANCELAR — Fase 4, `TenantSettingsScreen`). É
/// deliberadamente o caminho mais simples possível, para validar a
/// transação de booking ponta a ponta antes de construir a UI completa.
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

            return Column(
              children: [
                _WeeklyUsageBanner(
                  memberId: appUser.uid,
                  serviceId: service.id,
                  serviceName: service.name,
                ),
                Expanded(
                  child: occurrencesAsync.when(
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
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Fase 4 story 7 — "Ecrã aluno: barra '1/2 sessões esta semana' no
/// ecrã de marcação". Só aparece quando a [UsageRule] aplicável a este
/// membro+serviço é `limited` — para `unlimited` (ou quando o membro
/// não tem nenhum plano que dê acesso, caso já coberto pela mensagem de
/// elegibilidade ao tentar marcar) não mostra nada. Período é sempre a
/// semana ATUAL (`isoWeekKey(DateTime.now())`), não a semana de nenhuma
/// sessão específica.
class _WeeklyUsageBanner extends ConsumerWidget {
  const _WeeklyUsageBanner({
    required this.memberId,
    required this.serviceId,
    required this.serviceName,
  });

  final String memberId;
  final String serviceId;
  final String serviceName;

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
          usageProvider((memberId: memberId, serviceId: serviceId, period: period)),
        );
        final used = usageAsync.valueOrNull?.used ?? 0;
        final reached = used >= limit;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            color: reached
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(reached ? Icons.block_outlined : Icons.timelapse_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Esta semana: $used/$limit sessões de $serviceName'),
                  ),
                ],
              ),
            ),
          ),
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
        serviceId: widget.occurrence.serviceId,
        memberId: widget.memberId,
      );
      // Ver nota em my_bookings_screen.dart#_cancel: invalidar força uma
      // nova subscrição/fetch imediata em vez de esperar pela propagação
      // do listener do Firestore. Fase 4: o mesmo vale para a barra de
      // utilização — sem isto, "X/Y" só atualizava depois do próximo
      // evento de snapshot chegar sozinho.
      ref.invalidate(upcomingOccurrencesProvider(widget.occurrence.serviceId));
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
