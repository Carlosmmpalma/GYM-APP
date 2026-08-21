import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/subscription.dart';
import '../widgets/design_system.dart';

/// UC05/06/07 — "Marcar treino". Até à Fase 5 mostrava só as
/// ocorrências de UM serviço ("o primeiro ativo" — `primaryServiceProvider`,
/// hack da Fase 2 para não hardcodar um id); com várias séries a
/// poderem existir em serviços diferentes, isso escondia sessões reais
/// sem nenhum aviso ao aluno (bug real, reportado depois da Fase 5).
/// Mostra agora as ocorrências de TODOS os serviços
/// (`allUpcomingOccurrencesProvider`), com o nome do serviço (e do
/// instrutor, quando definido) em cada cartão — sem isso não dava para
/// perceber "que treino se trata" só pela hora/vagas.
///
/// Fase 10 — o mockup mostra este ecrã com separadores por modalidade
/// (HYROX · PILATES · PT · LIVRE) e a app tinha uma lista corrida só.
/// Com um horário real (várias modalidades × vários dias) isso obriga a
/// percorrer tudo à procura do que interessa. Os separadores são
/// construídos a partir das modalidades que TÊM sessões futuras — nunca
/// se mostra um separador que abre vazio, e um ginásio que não usa
/// modalidades não vê separadores nenhuns.
class BookTrainingScreen extends ConsumerStatefulWidget {
  const BookTrainingScreen({super.key});

  @override
  ConsumerState<BookTrainingScreen> createState() => _BookTrainingScreenState();
}

class _BookTrainingScreenState extends ConsumerState<BookTrainingScreen> {
  /// Guarda-se o ID e não o índice: a lista de separadores muda quando
  /// uma sessão é marcada/cancelada, e um índice ficaria a apontar para
  /// outra modalidade sem ninguém tocar em nada. `null` = "Todas".
  String? _modalityId;

  @override
  Widget build(BuildContext context) {
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
    final modalitiesAsync = ref.watch(modalitiesProvider);
    final eligibleAsync = ref.watch(myEligibleServiceIdsProvider);

    return appUserAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorState(error: error),
      data: (appUser) {
        if (appUser == null) {
          return const Center(
            child: Text('Sem sessão iniciada.', textAlign: TextAlign.center),
          );
        }

        return occurrencesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorState(error: error),
          data: (allOccurrences) {
            // Fase 11 — só o que o plano deste aluno dá. Antes via-se o
            // horário inteiro do ginásio e só se descobria ao tocar em
            // "Marcar", com um erro vindo da Cloud Function; mostrava-se
            // como oferta o que era uma venda por fazer.
            //
            // Enquanto a elegibilidade carrega (`null`) NÃO se filtra:
            // esconder o horário todo por um instante e vê-lo aparecer a
            // seguir é pior do que mostrá-lo um instante a mais. A
            // proteção real é do servidor, sempre.
            final eligible = eligibleAsync.valueOrNull;
            final occurrences = eligible == null
                ? allOccurrences
                : allOccurrences
                    .where((o) => eligible.contains(o.serviceId))
                    .toList();

            if (occurrences.isEmpty && eligible != null && eligible.isEmpty) {
              return const EmptyState(
                icon: Icons.lock_outline,
                title: 'O teu plano não dá acesso a aulas',
                message: 'Não tens nenhum plano ativo com acesso a aulas '
                    'marcáveis. Fala com o estúdio para saberes que planos '
                    'existem.',
              );
            }

            if (occurrences.isEmpty && allOccurrences.isNotEmpty) {
              return const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'Sem aulas do teu plano nos próximos dias',
                message: 'Há aulas no horário, mas nenhuma dos serviços a '
                    'que o teu plano dá acesso. Assim que houver, aparecem '
                    'aqui.',
              );
            }

            if (occurrences.isEmpty) {
              return const EmptyState(
                icon: Icons.fitness_center_outlined,
                title: 'Sem sessões para marcar',
                message: 'Não há aulas agendadas para os próximos dias nos '
                    'serviços a que o teu plano dá acesso. Assim que o '
                    'ginásio publicar o horário, aparecem aqui.',
              );
            }
            final servicesById = {
              for (final s in servicesAsync.valueOrNull ?? const []) s.id: s,
            };
            final staffByUid = {
              for (final s in staffAsync.valueOrNull ?? const []) s.uid: s,
            };

            // As ocorrências que este membro JÁ tem marcadas. Sem isto o
            // cartão oferecia "Marcar" numa sessão já marcada, e a única
            // resposta era o erro `AlreadyBookedException` vindo da Cloud
            // Function — depois de o utilizador premir o botão.
            final myBookedOccurrenceIds =
                (ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[])
                    .where((b) => b.status == BookingStatus.booked)
                    .map((b) => b.occurrenceId)
                    .toSet();

            final withSessions = occurrences
                .map((o) => o.modalityId)
                .whereType<String>()
                .toSet();
            final tabModalities = (modalitiesAsync.valueOrNull ?? const [])
                .where((m) => m.active && withSessions.contains(m.id))
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            final selected = tabModalities.any((m) => m.id == _modalityId)
                ? _modalityId
                : null;
            final visible = selected == null
                ? occurrences
                : occurrences.where((o) => o.modalityId == selected).toList();

            return Column(
              children: [
                if (tabModalities.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PillTabs(
                    labels: ['Todas', ...tabModalities.map((m) => m.name)],
                    selectedIndex: selected == null
                        ? 0
                        : tabModalities.indexWhere((m) => m.id == selected) + 1,
                    onSelected: (i) => setState(
                      () =>
                          _modalityId = i == 0 ? null : tabModalities[i - 1].id,
                    ),
                  ),
                ],
                Expanded(
                  child: visible.isEmpty
                      ? const EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'Sem sessões nesta modalidade',
                          message: 'Não há sessões futuras desta modalidade. '
                              'Toca em "Todas" para ver o horário completo.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final occurrence = visible[index];
                            return _OccurrenceTile(
                              // Sem `key`, o Flutter emparelha os
                              // elementos por POSIÇÃO: se uma sessão
                              // desaparece da lista (marcada, cancelada,
                              // ou o stream reordena), o estado interno
                              // — o spinner de "a marcar" — fica no
                              // índice e passa a aparecer na linha
                              // errada.
                              key: ValueKey(occurrence.id),
                              occurrence: occurrence,
                              memberId: appUser.uid,
                              alreadyBooked:
                                  myBookedOccurrenceIds.contains(occurrence.id),
                              serviceName:
                                  servicesById[occurrence.serviceId]?.name ??
                                      occurrence.serviceId,
                              instructorName: occurrence.instructorId == null
                                  ? null
                                  : staffByUid[occurrence.instructorId]?.name,
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

class _OccurrenceTile extends ConsumerStatefulWidget {
  const _OccurrenceTile({
    super.key,
    required this.occurrence,
    required this.memberId,
    required this.serviceName,
    required this.instructorName,
    required this.alreadyBooked,
  });

  final SessionOccurrence occurrence;
  final String memberId;
  final String serviceName;
  final String? instructorName;

  /// Este membro já tem marcação ativa nesta ocorrência.
  final bool alreadyBooked;

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
      ref.invalidate(myBookingsProvider);
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

    // O estado das vagas é a informação que decide se vale a pena ler o
    // resto do cartão — por isso é um `Pill` no topo, à direita, e não
    // uma linha de texto igual às outras a meio.
    final slotsLabel = occurrence.isFull
        ? 'Sem vagas'
        : '${occurrence.availableSlots}/${occurrence.capacity} vagas';
    final alreadyBooked = widget.alreadyBooked;

    return PanelCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.serviceName,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              if (alreadyBooked)
                const Pill('Marcado', tone: PillTone.ok)
              else
                Pill(
                  slotsLabel,
                  tone: occurrence.isFull ? PillTone.danger : PillTone.ok,
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            dateFormat.format(occurrence.startAt) +
                (widget.instructorName != null
                    ? ' · ${widget.instructorName}'
                    : ''),
            style: const TextStyle(color: AppColors.mute, fontSize: 12),
          ),
          _WeeklyUsageLine(
            memberId: widget.memberId,
            serviceId: occurrence.serviceId,
          ),
          const SizedBox(height: 12),
          // Já marcado → nada para premir aqui. O cancelamento vive em
          // "Marcações", que é onde já estava, e repetir a ação nos dois
          // ecrãs só criaria dois sítios para a mesma decisão.
          if (alreadyBooked)
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: AppColors.ok),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Já tens esta sessão marcada. Cancela em "Marcações".',
                    style: TextStyle(color: AppColors.mute, fontSize: 12),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (occurrence.isBookable && !_isBooking) ? _book : null,
                child: _isBooking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(occurrence.isFull ? 'Sem vagas' : 'Marcar'),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            AppBanner(text: _error!, tone: PillTone.danger),
          ],
        ],
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
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Esta semana',
                      style: TextStyle(color: AppColors.mute, fontSize: 11),
                    ),
                  ),
                  Text(
                    '$used/$limit sessões',
                    style: TextStyle(
                      color: reached ? AppColors.warn : AppColors.mute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              UsageBar(used: used, limit: limit),
              // UC08-A — o limite semanal esgotado não é o fim: o estúdio
              // pode marcar a sessão como extra. Dizê-lo aqui evita a
              // conclusão errada de que não há nada a fazer.
              if (reached) ...[
                const SizedBox(height: 8),
                const AppBanner(
                  text: 'Já usaste as sessões desta semana. O estúdio pode '
                      'marcar-te uma sessão extra, se houver vaga.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
