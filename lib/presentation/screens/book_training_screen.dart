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
import '../../repositories/waitlist_repository.dart';
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

  /// Quantas semanas de horário o ecrã está a mostrar.
  ///
  /// Começa em duas — a decisão real de um aluno é "esta semana ou a
  /// próxima". O horizonte completo (8 semanas, que é o que as séries
  /// geram) vem a pedido, com o botão no fim da lista. Assim a abertura
  /// da app lê o que interessa e não o horário inteiro do ginásio.
  int _weeksAhead = defaultBookingWeeksAhead;

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
    final eligibleAsync = ref.watch(myEligibleServiceIdsProvider);
    // O horário é pedido ao servidor JÁ filtrado pelos serviços do
    // plano deste aluno (ver `occurrencesForServicesProvider`). Antes
    // vinha o horário inteiro do ginásio para ser filtrado em memória:
    // quem só tinha aulas de grupo descarregava Pilates, PT e tudo o
    // resto para deitar fora, e quem não tinha plano nenhum
    // descarregava tudo para lhe dizerem que não tinha acesso a nada.
    //
    // Enquanto não se sabe a que tem direito, fica em carregamento —
    // perguntar antes de saber seria perguntar a coisa errada.
    final eligible = eligibleAsync.valueOrNull;
    final occurrencesAsync = eligible == null
        ? const AsyncValue<List<SessionOccurrence>>.loading()
        : ref.watch(occurrencesForServicesProvider(
            (serviceIdsKey: serviceIdsKey(eligible), weeksAhead: _weeksAhead),
          ));
    final servicesAsync = ref.watch(servicesProvider);
    final staffAsync = ref.watch(staffProvider);
    final modalitiesAsync = ref.watch(modalitiesProvider);

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
          data: (upcoming) {
            // Sessões canceladas pelo estúdio continuavam a aparecer
            // aqui, com as vagas todas livres e um botão "Marcar"
            // desativado sem explicação nenhuma. Quem tinha marcação
            // nelas já foi notificado; para os outros, é ruído.
            final occurrences = upcoming
                .where((o) => o.status == SessionOccurrenceStatus.scheduled)
                .toList();

            // `eligible` é sempre não-nulo aqui: o `data` só corre
            // depois de a elegibilidade ter resolvido (é ela que
            // escolhe a query).
            if (eligible!.isEmpty) {
              return const EmptyState(
                icon: Icons.lock_outline,
                title: 'O teu plano não dá acesso a aulas',
                message: 'Não tens nenhum plano ativo com acesso a aulas '
                    'marcáveis. Fala com o estúdio para saberes que planos '
                    'existem.',
              );
            }

            if (occurrences.isEmpty) {
              // Uma mensagem só, em vez de distinguir "o ginásio não
              // tem aulas" de "não tem aulas DO TEU PLANO": para
              // distinguir era preciso ler também o horário a que este
              // aluno não tem acesso — exatamente a leitura que se quis
              // evitar. O que ele pode fazer é o mesmo nos dois casos.
              return const EmptyState(
                icon: Icons.fitness_center_outlined,
                title: 'Sem aulas para marcar',
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

            final rows = _rowsByDay(visible);

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
                          // +1 pelo rodapé que alarga o horizonte.
                          itemCount: rows.length +
                              (_weeksAhead < maxBookingWeeksAhead ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            if (index == rows.length) {
                              return _MoreWeeksFooter(
                                weeksShown: _weeksAhead,
                                onExpand: () => setState(
                                    () => _weeksAhead = maxBookingWeeksAhead),
                              );
                            }
                            final row = rows[index];
                            // Cabeçalho de dia. Agrupar não é
                            // decoração: uma lista corrida de 40 aulas
                            // repete a data em cada cartão e obriga a
                            // lê-la para saber se é hoje ou daqui a
                            // duas semanas.
                            if (row.day != null) {
                              return Padding(
                                padding: EdgeInsets.only(
                                    top: index == 0 ? 0 : 12, bottom: 2),
                                child: SectionLabel(_dayLabel(row.day!)),
                              );
                            }
                            final occurrence = row.occurrence!;
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

/// Uma linha da lista: ou um cabeçalho de dia, ou uma sessão.
class _Row {
  const _Row.day(this.day) : occurrence = null;
  const _Row.occurrence(this.occurrence) : day = null;

  final DateTime? day;
  final SessionOccurrence? occurrence;
}

/// Intercala cabeçalhos de dia numa lista já ordenada por data.
List<_Row> _rowsByDay(List<SessionOccurrence> occurrences) {
  final rows = <_Row>[];
  DateTime? currentDay;
  for (final occurrence in occurrences) {
    final day = DateTime(
      occurrence.startAt.year,
      occurrence.startAt.month,
      occurrence.startAt.day,
    );
    if (currentDay == null || day != currentDay) {
      rows.add(_Row.day(day));
      currentDay = day;
    }
    rows.add(_Row.occurrence(occurrence));
  }
  return rows;
}

/// "Hoje" e "Amanhã" antes da data: é assim que se fala de treino, e
/// poupa a conta mental de ver "qua, 22 out" e perceber que é amanhã.
String _dayLabel(DateTime day) {
  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final difference = day.difference(startOfToday).inDays;
  if (difference == 0) return 'Hoje';
  if (difference == 1) return 'Amanhã';
  return DateFormat('EEEE, d MMM', 'pt_PT').format(day);
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
      ref.invalidate(occurrencesForServicesProvider);
      ref.invalidate(myBookingsProvider);
      // A semana da AULA, não a de hoje: marcar uma aula da semana que
      // vem não mexe na contagem desta.
      ref.invalidate(usageProvider((
        memberId: widget.memberId,
        serviceId: widget.occurrence.serviceId,
        period: isoWeekKey(widget.occurrence.startAt),
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
    final timeFormat = DateFormat('HH:mm', 'pt_PT');

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
            timeFormat.format(occurrence.startAt) +
                (widget.instructorName != null
                    ? ' · ${widget.instructorName}'
                    : ''),
            style: const TextStyle(color: AppColors.mute, fontSize: 12),
          ),
          _WeeklyUsageLine(
            memberId: widget.memberId,
            serviceId: occurrence.serviceId,
            occurrenceStart: occurrence.startAt,
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
          // Cheia mas ainda agendada: a ação útil deixa de ser marcar e
          // passa a ser esperar. Um botão "Sem vagas" desativado dizia
          // ao aluno que não havia nada a fazer — e havia.
          else if (occurrence.isFull &&
              occurrence.status == SessionOccurrenceStatus.scheduled)
            _WaitlistSection(
              occurrenceId: occurrence.id,
              memberId: widget.memberId,
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

/// Fase 11 — a alternativa a um botão "Sem vagas" desativado.
///
/// A app impõe capacidade por desenho, portanto aulas cheias são o
/// normal. Antes disto, quem chegava tarde não tinha nada a fazer senão
/// voltar a abrir a app de vez em quando a ver se alguém tinha
/// cancelado — e na maior parte das vezes não voltava.
///
/// A promessa que a mensagem faz é a que o servidor cumpre: quem
/// cancela liberta o lugar para o PRIMEIRO da fila, automaticamente e
/// sem confirmar (`firebase/functions/src/lib/waitlist.ts` explica
/// porquê essa escolha e não um convite com prazo). Por isso o texto
/// diz "ficas com o lugar", não "avisamos-te".
class _WaitlistSection extends ConsumerStatefulWidget {
  const _WaitlistSection({required this.occurrenceId, required this.memberId});

  final String occurrenceId;
  final String memberId;

  @override
  ConsumerState<_WaitlistSection> createState() => _WaitlistSectionState();
}

class _WaitlistSectionState extends ConsumerState<_WaitlistSection> {
  bool _isBusy = false;
  String? _error;

  Future<void> _run(
      Future<void> Function(WaitlistRepository repo) action) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await action(ref.read(waitlistRepositoryProvider));
      // Mesma razão de `_book`: forçar a releitura em vez de esperar
      // pela propagação do listener.
      ref.invalidate(myWaitlistEntryProvider(widget.occurrenceId));
      ref.invalidate(occurrencesForServicesProvider);
      ref.invalidate(myBookingsProvider);
    } on WaitlistHasCapacityException catch (e) {
      setState(() => _error = e.toString());
    } on WaitlistAlreadyBookedException catch (e) {
      setState(() => _error = e.toString());
    } on WaitlistNotEligibleException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Não foi possível. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(myWaitlistEntryProvider(widget.occurrenceId));

    // Enquanto carrega mostra-se o botão de entrar, não um spinner: o
    // caso esmagadoramente comum é não estar na fila, e piscar um
    // indicador em cada cartão cheio da lista seria pior do que corrigir
    // o botão um instante depois.
    final position = entry.valueOrNull?.position;
    final inQueue = entry.valueOrNull != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inQueue)
          Row(
            children: [
              const Icon(Icons.hourglass_top, size: 16, color: AppColors.mute),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  position == null
                      ? 'Estás na lista de espera. Se vagar um lugar, a '
                          'marcação é feita automaticamente.'
                      : position == 1
                          ? 'És o próximo da lista. Se alguém cancelar, o '
                              'lugar fica teu automaticamente.'
                          : 'Estás em $positionº na lista de espera.',
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ),
            ],
          )
        else
          const Text(
            'Sessão cheia. Entra na lista de espera e, se alguém cancelar, '
            'ficas com o lugar automaticamente.',
            style: TextStyle(color: AppColors.mute, fontSize: 12),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: inQueue
              ? OutlinedButton(
                  onPressed: _isBusy
                      ? null
                      : () => _run((repo) => repo.leave(
                            occurrenceId: widget.occurrenceId,
                            memberId: widget.memberId,
                          )),
                  child: _isBusy
                      ? const _TinySpinner()
                      : const Text('Sair da lista de espera'),
                )
              : FilledButton.tonal(
                  onPressed: _isBusy
                      ? null
                      : () => _run((repo) => repo.join(
                            occurrenceId: widget.occurrenceId,
                            memberId: widget.memberId,
                          )),
                  child: _isBusy
                      ? const _TinySpinner()
                      : const Text('Entrar em lista de espera'),
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          AppBanner(text: _error!, tone: PillTone.danger),
        ],
      ],
    );
  }
}

class _TinySpinner extends StatelessWidget {
  const _TinySpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
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
  const _WeeklyUsageLine({
    required this.memberId,
    required this.serviceId,
    required this.occurrenceStart,
  });

  final String memberId;
  final String serviceId;

  /// Quando a AULA acontece.
  ///
  /// O limite é por semana, e esta lista mostra duas semanas de cada
  /// vez. Isto lia `DateTime.now()` e mostrava a contagem da semana
  /// CORRENTE em todos os cartões: um aluno com o limite gasto esta
  /// semana via "1/1 sessões — já usaste as sessões desta semana" numa
  /// aula da semana seguinte, ao lado de um botão "Marcar" que
  /// funcionava perfeitamente. A interface a contradizer-se, e do lado
  /// que faz as pessoas não marcarem.
  final DateTime occurrenceStart;

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
        final period = isoWeekKey(occurrenceStart);
        final estaSemana = period == isoWeekKey(DateTime.now());
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
                  Expanded(
                    child: Text(
                      estaSemana ? 'Esta semana' : 'Nessa semana',
                      style:
                          const TextStyle(color: AppColors.mute, fontSize: 11),
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
                AppBanner(
                  text: estaSemana
                      ? 'Já usaste as sessões desta semana. O estúdio pode '
                          'marcar-te uma sessão extra, se houver vaga.'
                      : 'Já tens as sessões dessa semana ocupadas. O estúdio '
                          'pode marcar-te uma sessão extra, se houver vaga.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Rodapé que alarga o horário das duas semanas iniciais para as oito
/// que as séries geram.
///
/// Existe para que a abertura da app leia só o que interessa. Um botão
/// discreto no fim da lista, e não um seletor no topo: quem procura a
/// aula de amanhã não devia ter de decidir nada primeiro.
class _MoreWeeksFooter extends StatelessWidget {
  const _MoreWeeksFooter({required this.weeksShown, required this.onExpand});

  final int weeksShown;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        children: [
          Text(
            'A mostrar as próximas $weeksShown semanas.',
            style: const TextStyle(color: AppColors.mute, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onExpand,
            child: const Text('Ver horário completo'),
          ),
        ],
      ),
    );
  }
}
