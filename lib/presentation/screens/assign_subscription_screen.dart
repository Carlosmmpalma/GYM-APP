import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firebase_error_text.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/subscription.dart';
import '../widgets/async_action_button.dart';
import '../widgets/design_system.dart';
import '../widgets/member_picker.dart';

/// Ecrã Gestor: **o plano** de um membro.
///
/// ## Um plano por membro
///
/// Já foram vários, e isso obrigava a duas regras de conflito que
/// ninguém de fora conseguia adivinhar: dois planos não podiam dar o
/// mesmo serviço, e — desde a Fase 8 — não podiam dar serviços com o
/// mesmo `Service.exclusiveGroup`, uma etiqueta de texto livre que o
/// Gestor tinha de escrever à mão no ecrã dos serviços.
///
/// O ecrã refletia isso: partia-se em "níveis" (escolha única) e
/// "avulsos" (escolha múltipla), sem nunca dizer porquê. Um plano caía
/// numa lista ou na outra consoante os serviços que embrulhasse, e quem
/// olhava via o "Hyrox Team" numa escolha única de acompanhamento sem
/// perceber o que o Hyrox tinha a ver com isso — tinha, mas só porque
/// incluía "Treino livre" lá dentro.
///
/// Com um plano só, as duas regras deixam de ter objeto. O ecrã passa a
/// ser o que sempre quis ser: uma lista de planos, escolhe um.
///
/// A proteção que interessa mudou de sítio, para onde se entende sem
/// explicação nenhuma — ao MARCAR, onde ninguém pode estar em dois
/// sítios à mesma hora (ver `firebase/functions/src/lib/overlap.ts`).
///
/// [initialMember], opcional, permite chegar aqui já com o membro
/// escolhido a partir de `MemberDetailScreen`.
class AssignSubscriptionScreen extends ConsumerStatefulWidget {
  const AssignSubscriptionScreen({super.key, this.initialMember});

  final MemberSummary? initialMember;

  @override
  ConsumerState<AssignSubscriptionScreen> createState() =>
      _AssignSubscriptionScreenState();
}

class _AssignSubscriptionScreenState
    extends ConsumerState<AssignSubscriptionScreen> {
  late MemberSummary? _member = widget.initialMember;

  /// O plano escolhido. Um, ou nenhum.
  String? _chosenPlanId;

  /// Preço acordado. `agreedPrice` é um conceito real do domínio (pode
  /// divergir do `currentPrice` do Plan e fica congelado na subscrição),
  /// por isso continua editável.
  final Map<String, TextEditingController> _priceControllers = {};

  String? _errorMessage;

  @override
  void dispose() {
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _priceControllerFor(Plan plan) {
    return _priceControllers.putIfAbsent(
      plan.id,
      () => TextEditingController(text: plan.currentPrice.toStringAsFixed(2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final plansAsync = ref.watch(plansProvider);
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plano do membro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ErrorState(
              error: error,
              message: 'Não foi possível carregar membros.',
              compact: true,
            ),
            data: (members) => MemberPickerField(
              members: members,
              selected: _member,
              onSelected: (v) => setState(() {
                _member = v;
                _chosenPlanId = null;
                _errorMessage = null;
              }),
            ),
          ),
          if (_member == null) ...[
            const SizedBox(height: 32),
            const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'Escolhe um membro',
              message: 'Escolhe primeiro de quem é o plano. A oferta aparece '
                  'a seguir, já a dizer o que ele tem hoje.',
            ),
          ] else
            ...switch ((plansAsync, servicesAsync)) {
              (AsyncError(:final error), _) ||
              (_, AsyncError(:final error)) =>
                [
                  ErrorState(
                    error: error,
                    message: 'Não foi possível carregar a oferta.',
                    compact: true,
                  )
                ],
              (
                AsyncData(value: final plans),
                AsyncData(value: final services)
              ) =>
                _ofertaSections(plans, services),
              _ => [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
            },
        ],
      ),
    );
  }

  List<Widget> _ofertaSections(List<Plan> plans, List<Service> services) {
    final subscriptionsAsync =
        ref.watch(memberSubscriptionsProvider(_member!.uid));
    final activeSubscriptions =
        (subscriptionsAsync.valueOrNull ?? const <Subscription>[])
            .where((s) => s.isActive)
            .toList();
    final plansById = {for (final p in plans) p.id: p};

    // O plano em vigor. Normalmente zero ou um; se houver mais (dados de
    // quando vários eram permitidos), o primeiro serve para a comparação
    // e atribuir um novo cancela-os todos.
    final atualId =
        activeSubscriptions.isEmpty ? null : activeSubscriptions.first.planId;

    final activePlans = plans.where((p) => p.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final escolhido = _chosenPlanId == null ? null : plansById[_chosenPlanId];

    return [
      const SizedBox(height: 16),
      _ActivePlansCard(
        subscriptions: activeSubscriptions,
        loading: subscriptionsAsync.isLoading,
        plansById: plansById,
        services: services,
      ),
      if (activePlans.isEmpty) ...[
        const SizedBox(height: 24),
        const EmptyState(
          icon: Icons.card_membership_outlined,
          title: 'Não há planos ativos para atribuir',
          message: 'Só se pode atribuir um plano que exista e esteja ativo.',
          prerequisite: 'Cria planos em Gestão › Planos.',
        ),
      ] else ...[
        const SizedBox(height: 20),
        SectionLabel(atualId == null ? 'Escolhe o plano' : 'Mudar para'),
        const SizedBox(height: 6),
        RadioGroup<String?>(
          groupValue: _chosenPlanId,
          onChanged: (value) => setState(() {
            _chosenPlanId = value;
            _errorMessage = null;
          }),
          child: Column(
            children: [
              for (final plan in activePlans)
                _PlanOption(plan: plan, atual: plan.id == atualId),
            ],
          ),
        ),
        if (atualId != null) ...[
          const SizedBox(height: 4),
          const Text(
            'Um membro tem um plano de cada vez — escolher outro substitui '
            'o atual. As marcações já feitas mantêm-se.',
            style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
          ),
        ],
      ],
      if (escolhido != null) ...[
        const SizedBox(height: 20),
        const SectionLabel('Preço acordado'),
        const SizedBox(height: 2),
        const Text(
          'Vem preenchido com o preço de tabela; muda-o se este membro '
          'tiver outro valor. Fica congelado na subscrição.',
          style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: _priceControllerFor(escolhido),
            decoration: InputDecoration(
              labelText: escolhido.name,
              suffixText: escolhido.currency,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
      ],
      const SizedBox(height: 20),
      if (_errorMessage != null) ...[
        AppBanner(text: _errorMessage!),
        const SizedBox(height: 12),
      ],
      // O estado de ocupado e o visto de "feito" vivem no botão — ver
      // `AsyncActionButton`. `_submitting` continua a existir porque o
      // resto do ecrã também o lê.
      AsyncActionButton(
        label: atualId == null ? 'Atribuir plano' : 'Mudar de plano',
        expand: true,
        enabled: activePlans.isNotEmpty,
        onPressed: _submit,
        onError: (e) => setState(() => _errorMessage = userFacingError(
              e,
              fallback: 'Não foi possível atribuir o plano. Tenta outra vez.',
            )),
      ),
      const SizedBox(height: 24),
    ];
  }

  Future<void> _submit() async {
    final plans = ref.read(plansProvider).valueOrNull ?? const <Plan>[];
    Plan? plano;
    for (final p in plans) {
      if (p.id == _chosenPlanId) plano = p;
    }

    if (plano == null) {
      setState(() => _errorMessage = 'Escolhe um plano para atribuir.');
      return;
    }

    final raw = _priceControllerFor(plano).text.replaceAll(',', '.').trim();
    final parsed = double.tryParse(raw);
    // Mesmo limite do schema zod de createSubscription.ts
    // (`agreedPrice: z.number().nonnegative()`): 0 é aceite (promoção),
    // negativo não.
    if (parsed == null || parsed < 0) {
      setState(() => _errorMessage = 'Preço inválido.');
      return;
    }

    setState(() => _errorMessage = null);

    // Sem try/catch: o `AsyncActionButton` apanha e encaminha para
    // `onError`, que põe a mensagem no banner deste ecrã em vez de num
    // SnackBar que desaparece. Deixar o erro à vista é o ponto todo num
    // formulário — é preciso mexer nele para o resolver.
    await ref.read(subscriptionRepositoryProvider).createSubscription(
          memberId: _member!.uid,
          planId: plano.id,
          agreedPrice: parsed,
          currency: plano.currency,
        );

    if (!mounted) return;

    // O trabalho acabou, e o ecrã acaba com ele.
    //
    // Ficava aberto em modo de formulário depois de guardar. Com as
    // secções antigas isso era pior ainda: a parte que a pessoa tinha
    // acabado de usar colapsava e outra tomava-lhe o lugar, o que se lia
    // como ter sido levada para outro ecrã a pedir mais qualquer coisa.
    // Foi assim que foi reportado.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (widget.initialMember != null && navigator.canPop()) {
      messenger.showSnackBar(
        SnackBar(content: Text('Plano: ${plano.name}.')),
      );
      navigator.pop();
      return;
    }

    // Aberto a partir da Gestão, sem membro por onde voltar: fica, e a
    // confirmação é o próprio ecrã — o cartão de topo passa a mostrar o
    // plano novo, e o botão dá o visto. Um SnackBar por cima disso
    // anunciava o que já está à vista.
    setState(() => _chosenPlanId = null);
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({required this.plan, required this.atual});

  final Plan plan;

  /// É o plano que o membro tem neste momento.
  final bool atual;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: RadioListTile<String?>(
        value: plan.id,
        title: Row(
          children: [
            Expanded(child: Text(plan.name)),
            if (atual) const Pill('atual', tone: PillTone.ok),
          ],
        ),
        subtitle: Text(
          '${plan.currentPrice.toStringAsFixed(2)} ${plan.currency}'
          '${plan.description.isEmpty ? '' : ' · ${plan.description}'}',
        ),
        dense: true,
      ),
    );
  }
}

/// Planos ativos do membro escolhido, mostrados ANTES de atribuir mais —
/// é o que evita descobrir um conflito só depois de submeter. Só
/// `status == active`; o histórico (cancelled/expired/paused) fica em
/// `MemberDetailScreen`, que é o sítio de consulta, não este formulário.
class _ActivePlansCard extends StatelessWidget {
  const _ActivePlansCard({
    required this.subscriptions,
    required this.loading,
    required this.plansById,
    required this.services,
  });

  final List<Subscription> subscriptions;
  final bool loading;
  final Map<String, Plan> plansById;
  final List<Service> services;

  @override
  Widget build(BuildContext context) {
    if (loading && subscriptions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final servicesById = {for (final s in services) s.id: s};

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('O que este membro já tem'),
          const SizedBox(height: 6),
          if (subscriptions.isEmpty)
            const Text(
              'Nenhum plano ativo.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            )
          else
            for (final subscription in subscriptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· ${plansById[subscription.planId]?.name ?? subscription.planId}'
                  '${subscription.activeServiceIds.isEmpty ? '' : ' (${subscription.activeServiceIds.map((id) => servicesById[id]?.name ?? id).join(', ')})'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}
