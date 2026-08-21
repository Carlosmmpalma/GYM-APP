import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/subscription.dart';
import '../widgets/design_system.dart';
import '../widgets/member_picker.dart';

/// UC26 (atualizado) — Ecrã Gestor: atribuir planos a um membro (cria
/// [Subscription]s via Cloud Function `createSubscription`).
///
/// Fase 10 — reescrito para o formato do mockup ("Atribuir
/// serviço/plano"): em vez de um dropdown de UM plano por submissão,
/// mostra a oferta toda de uma vez, agrupada, com os níveis do mesmo
/// produto em seleção única e os extras em seleção múltipla. Antes, dar
/// a um membro "sala Plus + Aula Hyrox + PT Pilates" eram três voltas ao
/// mesmo formulário, e a exclusividade só aparecia como erro depois de
/// submeter.
///
/// O agrupamento vem de `planExclusiveGroupsProvider`: o grupo de um
/// Plan deriva do `Service.exclusiveGroup` dos serviços a que dá
/// acesso, e não de nenhuma lista fixa de categorias — Domain Model v1
/// §10 é explícito em que "Standard"/"Plus"/"Premium" são nomes que cada
/// tenant escolhe, nunca um enum no código.
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

  /// Escolha por grupo exclusivo (`grupo → planId`). A ausência de
  /// chave é o "Nenhum"/"Sem acompanhamento" do mockup — não precisa de
  /// um valor sentinela próprio.
  final Map<String, String> _chosenByGroup = {};

  /// Planos independentes escolhidos (seleção múltipla).
  final Set<String> _chosenExtras = {};

  /// Preço acordado por plano selecionado. `agreedPrice` é um conceito
  /// real do domínio (pode divergir do `currentPrice` do Plan e fica
  /// congelado na subscription) — por isso continua editável, mesmo que
  /// o mockup não mostre preços neste ecrã.
  final Map<String, TextEditingController> _priceControllers = {};

  bool _submitting = false;
  String? _errorMessage;
  String? _successMessage;

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
    final groupsAsync = ref.watch(planExclusiveGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Atribuir plano')),
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
            // Fase 11 — era um dropdown. Funciona com dez nomes; com
            // trezentos é uma lista por onde se rola à procura, sem
            // forma de escrever o que se sabe.
            data: (members) => MemberPickerField(
              members: members,
              selected: _member,
              onSelected: (v) => setState(() {
                _member = v;
                // A oferta que faz sentido depende do que o membro já
                // tem; manter as escolhas do membro anterior seria
                // atribuir-lhe coisas por engano.
                _chosenByGroup.clear();
                _chosenExtras.clear();
                _errorMessage = null;
                _successMessage = null;
              }),
            ),
          ),
          if (_member == null) ...[
            const SizedBox(height: 32),
            const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'Escolhe um membro',
              message: 'Escolhe primeiro a quem vais atribuir planos. A '
                  'oferta aparece a seguir, já a dizer o que ele tem hoje.',
            ),
          ] else
            ...switch ((plansAsync, servicesAsync, groupsAsync)) {
              (AsyncError(:final error), _, _) ||
              (_, AsyncError(:final error), _) ||
              (_, _, AsyncError(:final error)) =>
                [
                  ErrorState(
                    error: error,
                    message: 'Não foi possível carregar a oferta.',
                    compact: true,
                  )
                ],
              (
                AsyncData(value: final plans),
                AsyncData(value: final services),
                AsyncData(value: final groups),
              ) =>
                _offerSections(plans, services, groups),
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

  List<Widget> _offerSections(
    List<Plan> plans,
    List<Service> services,
    Map<String, String?> groupOfPlan,
  ) {
    final subscriptionsAsync =
        ref.watch(memberSubscriptionsProvider(_member!.uid));
    final activeSubscriptions =
        (subscriptionsAsync.valueOrNull ?? const <Subscription>[])
            .where((s) => s.isActive)
            .toList();

    final plansById = {for (final p in plans) p.id: p};
    final activePlanIds = activeSubscriptions.map((s) => s.planId).toSet();

    // Que grupos exclusivos o membro já ocupa, e com que plano. Vem das
    // subscriptions ativas e não das escolhas do ecrã: é o estado real
    // contra o qual a Cloud Function vai validar.
    final occupiedGroups = <String, String>{};
    for (final subscription in activeSubscriptions) {
      final group = groupOfPlan[subscription.planId];
      if (group != null) occupiedGroups[group] = subscription.planId;
    }

    final activePlans = plans.where((p) => p.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final groupNames = activePlans
        .map((p) => groupOfPlan[p.id])
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final extras = activePlans.where((p) => groupOfPlan[p.id] == null).toList();

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
      ],
      for (final group in groupNames) ...[
        const SizedBox(height: 20),
        ..._exclusiveGroupSection(
          group: group,
          plans: activePlans.where((p) => groupOfPlan[p.id] == group).toList(),
          occupiedByPlanId: occupiedGroups[group],
          plansById: plansById,
        ),
      ],
      if (extras.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionLabel('Planos avulsos (pode escolher vários)'),
        const SizedBox(height: 6),
        for (final plan in extras)
          _PlanOption(
            plan: plan,
            single: false,
            selected: _chosenExtras.contains(plan.id),
            alreadyAssigned: activePlanIds.contains(plan.id),
            onChanged: (value) => setState(() {
              if (value) {
                _chosenExtras.add(plan.id);
              } else {
                _chosenExtras.remove(plan.id);
              }
            }),
          ),
      ],
      ..._pricesSection(plansById),
      const SizedBox(height: 20),
      if (_errorMessage != null) ...[
        AppBanner(text: _errorMessage!),
        const SizedBox(height: 12),
      ],
      if (_successMessage != null) ...[
        AppBanner(
          text: _successMessage!,
          tone: PillTone.ok,
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _submitting || activePlans.isEmpty ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_selectedPlanIds().isEmpty
                  ? 'Guardar'
                  : 'Guardar ${_selectedPlanIds().length} plano(s)'),
        ),
      ),
    ];
  }

  /// Um grupo exclusivo: seleção única, com "Nenhum" explícito (é o "Sem
  /// acompanhamento" do mockup). Se o membro já ocupa este grupo, o
  /// grupo aparece só informativo — a Cloud Function recusaria qualquer
  /// outro nível com um conflito, e mostrar botões que só levam a um
  /// erro garantido é pior do que explicar o que fazer.
  List<Widget> _exclusiveGroupSection({
    required String group,
    required List<Plan> plans,
    required String? occupiedByPlanId,
    required Map<String, Plan> plansById,
  }) {
    if (occupiedByPlanId != null) {
      final current = plansById[occupiedByPlanId]?.name ?? occupiedByPlanId;
      return [
        SectionLabel('Nível de $group'),
        const SizedBox(height: 6),
        PanelCard(
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 18, color: AppColors.mute),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Já tem "$current". Os níveis deste grupo não se acumulam '
                  '— para trocar, cancela primeiro o plano atual na ficha '
                  'do membro.',
                  style: const TextStyle(
                      color: AppColors.mute, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final chosen = _chosenByGroup[group];
    return [
      SectionLabel('Nível de $group — escolhe uma opção'),
      const SizedBox(height: 6),
      RadioGroup<String?>(
        groupValue: chosen,
        onChanged: (value) => setState(() {
          if (value == null) {
            _chosenByGroup.remove(group);
          } else {
            _chosenByGroup[group] = value;
          }
        }),
        child: Column(
          children: [
            const _NoneOption(),
            for (final plan in plans)
              _PlanOption(
                  plan: plan, single: true, selected: chosen == plan.id),
          ],
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'São níveis do mesmo produto — nunca em conjunto.',
        style: TextStyle(color: AppColors.dim, fontSize: 11),
      ),
    ];
  }

  List<Widget> _pricesSection(Map<String, Plan> plansById) {
    final selected = _selectedPlanIds()
        .map((id) => plansById[id])
        .whereType<Plan>()
        .toList();
    if (selected.isEmpty) return const [];

    return [
      const SizedBox(height: 20),
      const SectionLabel('Preço acordado'),
      const SizedBox(height: 2),
      const Text(
        'Vem preenchido com o preço de tabela; muda-o se este membro '
        'tiver outro valor. Fica congelado na subscrição.',
        style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
      ),
      for (final plan in selected)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: _priceControllerFor(plan),
            decoration: InputDecoration(
              labelText: plan.name,
              suffixText: plan.currency,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
    ];
  }

  /// Ordem estável: primeiro os níveis (por grupo, alfabético), depois os
  /// avulsos. Sem isto a ordem viria de um `Set` e mudava entre builds,
  /// o que se veria nos campos de preço a saltar de posição.
  List<String> _selectedPlanIds() {
    final groups = _chosenByGroup.keys.toList()..sort();
    final extras = _chosenExtras.toList()..sort();
    return [
      for (final group in groups) _chosenByGroup[group]!,
      ...extras,
    ];
  }

  Future<void> _submit() async {
    final plans = ref.read(plansProvider).valueOrNull ?? const <Plan>[];
    final plansById = {for (final p in plans) p.id: p};
    final selected = _selectedPlanIds()
        .map((id) => plansById[id])
        .whereType<Plan>()
        .toList();

    if (selected.isEmpty) {
      setState(() {
        _errorMessage = 'Não escolheste nenhum plano. Escolhe pelo menos um '
            'nível ou um plano avulso.';
        _successMessage = null;
      });
      return;
    }

    // Validação de preço antes de começar a escrever: com N chamadas, um
    // valor inválido no 3º plano não deve deixar os dois primeiros já
    // atribuídos.
    final prices = <String, double>{};
    for (final plan in selected) {
      final raw = _priceControllerFor(plan).text.replaceAll(',', '.').trim();
      final parsed = double.tryParse(raw);
      // Mesmo limite do schema zod de createSubscription.ts
      // (`agreedPrice: z.number().nonnegative()`): 0 é aceite (promoção),
      // negativo não.
      if (parsed == null || parsed < 0) {
        setState(() {
          _errorMessage = 'Preço inválido em "${plan.name}".';
          _successMessage = null;
        });
        return;
      }
      prices[plan.id] = parsed;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    // Cada plano é uma chamada própria à Cloud Function — não há
    // transação que cubra as N. Se a terceira falhar, as duas primeiras
    // ficaram atribuídas; a mensagem final diz exatamente isso em vez de
    // fingir tudo-ou-nada (mesmo princípio de `rescheduleBooking`).
    final done = <String>[];
    final failed = <String>[];
    for (final plan in selected) {
      try {
        await ref.read(subscriptionRepositoryProvider).createSubscription(
              memberId: _member!.uid,
              planId: plan.id,
              agreedPrice: prices[plan.id]!,
              currency: plan.currency,
            );
        done.add(plan.name);
      } on SubscriptionServiceConflictException catch (e) {
        failed.add('${plan.name}: $e');
      } catch (e) {
        failed.add('${plan.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      // O que ficou feito sai da seleção; o que falhou continua marcado,
      // para se poder corrigir e voltar a tentar sem remarcar tudo.
      for (final plan in selected) {
        if (done.contains(plan.name)) {
          _chosenExtras.remove(plan.id);
          _chosenByGroup.removeWhere((_, planId) => planId == plan.id);
        }
      }
      _successMessage = done.isEmpty ? null : 'Atribuído: ${done.join(', ')}.';
      _errorMessage = failed.isEmpty ? null : failed.join('\n');
    });
  }
}

/// A opção "Nenhum" de um grupo exclusivo. Existir explicitamente é o
/// que torna possível dizer "este membro não tem nível nenhum" sem ser
/// pela ausência de qualquer marca — é o "Sem acompanhamento" do mockup.
class _NoneOption extends StatelessWidget {
  const _NoneOption();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: RadioListTile<String?>(
        value: null,
        title: Text('Nenhum'),
        dense: true,
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.plan,
    required this.single,
    required this.selected,
    this.alreadyAssigned = false,
    this.onChanged,
  });

  final Plan plan;
  final bool single;
  final bool selected;
  final bool alreadyAssigned;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = Text(
      '${plan.currentPrice.toStringAsFixed(2)} ${plan.currency}'
      '${plan.description.isEmpty ? '' : ' · ${plan.description}'}',
    );

    if (alreadyAssigned) {
      return Card(
        child: ListTile(
          dense: true,
          title: Text(plan.name),
          subtitle: subtitle,
          trailing: const Pill('já tem', tone: PillTone.ok),
        ),
      );
    }

    return Card(
      child: single
          ? RadioListTile<String?>(
              value: plan.id,
              title: Text(plan.name),
              subtitle: subtitle,
              dense: true,
            )
          : CheckboxListTile(
              value: selected,
              onChanged: (value) => onChanged?.call(value ?? false),
              title: Text(plan.name),
              subtitle: subtitle,
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
