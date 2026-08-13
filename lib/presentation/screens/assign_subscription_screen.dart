import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/subscription.dart';

/// UC26 — Ecrã Gestor: atribuir um Plan a um membro (cria uma
/// [Subscription] via Cloud Function `createSubscription`).
///
/// Fluxo simples de um único ecrã: escolher membro, escolher plano
/// (o preço acordado vem pré-preenchido com o `currentPrice` do Plan
/// mas é editável — ver nota em `subscription.dart` sobre
/// `agreedPrice` vs `currentPrice`), confirmar. Erros de conflito
/// (`SubscriptionServiceConflictException`) são mostrados tal como o
/// `toString()` da exceção já os formata — mensagem específica,
/// consistente com o padrão adotado para `NotEligibleForServiceException`
/// no ecrã de booking (Fase 3).
///
/// Pedido depois de testares a Fase 3: assim que escolhes o membro,
/// mostra logo os planos ativos que ele já tem — antes, só descobrias
/// um conflito depois de tentar submeter e o Cloud Function recusar.
/// [initialMember], opcional, permite chegar aqui já com o membro
/// escolhido a partir de `MemberDetailScreen` ("Atribuir novo plano").
///
/// Gap do mockup (UC26 mostra atribuir vários serviços/níveis a um
/// membro num único fluxo, ex. sala + aulas de grupo + PT): não
/// hardcodo essas categorias (violaria o Domain Model v1 §10 — nunca
/// enum fixo, Plans são configuráveis por tenant), mas depois de
/// atribuir um plano com sucesso o ecrã já não faz `pop` — fica no
/// mesmo membro, limpa só o plano/preço, e a secção "Planos ativos
/// deste membro" atualiza-se sozinha (é um StreamProvider), para o
/// Gestor poder atribuir logo o plano seguinte. Sair é sempre via
/// botão de voltar da AppBar.
class AssignSubscriptionScreen extends ConsumerStatefulWidget {
  const AssignSubscriptionScreen({super.key, this.initialMember});

  final MemberSummary? initialMember;

  @override
  ConsumerState<AssignSubscriptionScreen> createState() =>
      _AssignSubscriptionScreenState();
}

class _AssignSubscriptionScreenState
    extends ConsumerState<AssignSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();

  late MemberSummary? _member = widget.initialMember;
  Plan? _plan;
  bool _submitting = false;
  String? _errorMessage;

  // Incrementado a cada atribuição bem-sucedida. `DropdownButtonFormField`
  // (tal como `TextFormField`) só lê `initialValue` na primeira
  // construção — mudar `_plan` para null sozinho não limpa o dropdown
  // visualmente. Ao mudar a `key` do campo força o Flutter a recriar o
  // elemento com o novo `initialValue`, que é o efeito que queremos.
  int _formGeneration = 0;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final plansAsync = ref.watch(plansProvider);
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Atribuir plano')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Erro a carregar membros: $error'),
                data: (members) => DropdownButtonFormField<MemberSummary>(
                  initialValue: _member,
                  decoration: const InputDecoration(labelText: 'Membro'),
                  items: members
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text('${m.name} (${m.memberNumber})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _member = v),
                  validator: (v) => v == null ? 'Escolhe um membro' : null,
                ),
              ),
              if (_member != null) ...[
                const SizedBox(height: 8),
                _CurrentSubscriptionsSection(
                  memberId: _member!.uid,
                  plans: plansAsync.valueOrNull ?? const [],
                  services: servicesAsync.valueOrNull ?? const [],
                ),
              ],
              const SizedBox(height: 16),
              plansAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Erro a carregar planos: $error'),
                data: (plans) => DropdownButtonFormField<Plan>(
                  key: ValueKey(_formGeneration),
                  initialValue: _plan,
                  decoration: const InputDecoration(labelText: 'Plano'),
                  items: plans
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _plan = v;
                    if (v != null && _priceController.text.isEmpty) {
                      _priceController.text = v.currentPrice.toStringAsFixed(2);
                    }
                  }),
                  validator: (v) => v == null ? 'Escolhe um plano' : null,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: 'Preço acordado',
                  suffixText: _plan?.currency,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Obrigatório';
                  final parsed = double.tryParse(v.replaceAll(',', '.'));
                  if (parsed == null) return 'Valor inválido';
                  // Mesmo limite que o schema zod de createSubscription.ts
                  // (`agreedPrice: z.number().nonnegative()`) — 0 é aceite
                  // (ex.: promoção), negativo não. Sem isto, o formulário
                  // deixava passar valores que a Cloud Function ia
                  // rejeitar de qualquer forma, só que com um erro
                  // genérico em vez desta mensagem específica.
                  return parsed < 0 ? 'Não pode ser negativo' : null;
                },
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Atribuir'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(subscriptionRepositoryProvider).createSubscription(
            memberId: _member!.uid,
            planId: _plan!.id,
            agreedPrice: double.parse(_priceController.text.replaceAll(',', '.')),
            currency: _plan!.currency,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Plano atribuído com sucesso. Podes atribuir outro ao mesmo '
            'membro ou voltar atrás.',
          ),
        ),
      );
      // Fica no mesmo membro (ver nota na classe) — só limpa o plano e
      // o preço, para o Gestor poder atribuir logo o próximo plano sem
      // ter de voltar a escolher o membro.
      setState(() {
        _plan = null;
        _priceController.clear();
        _formGeneration++;
      });
    } on SubscriptionServiceConflictException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      setState(() => _errorMessage = 'Não foi possível atribuir o plano: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// Planos/subscriptions ativas do membro escolhido, mostrados ANTES de
/// tentares atribuir mais um — é o que faltava para não teres de
/// descobrir um conflito só depois de submeter (ver nota na classe
/// acima). Só mostra `status == active`; histórico completo
/// (cancelled/expired/paused) fica em `MemberDetailScreen`, que é o
/// sítio certo para consulta, não este formulário.
class _CurrentSubscriptionsSection extends ConsumerWidget {
  const _CurrentSubscriptionsSection({
    required this.memberId,
    required this.plans,
    required this.services,
  });

  final String memberId;
  final List<Plan> plans;
  final List<Service> services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionsAsync = ref.watch(memberSubscriptionsProvider(memberId));

    return subscriptionsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (error, stack) =>
          Text('Erro a carregar planos atuais: $error'),
      data: (subscriptions) {
        final active = subscriptions.where((s) => s.isActive).toList();
        if (active.isEmpty) {
          return const Text(
            'Este membro não tem nenhum plano ativo neste momento.',
            style: TextStyle(fontStyle: FontStyle.italic),
          );
        }

        final plansById = {for (final p in plans) p.id: p};
        final servicesById = {for (final s in services) s.id: s};

        return Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planos ativos deste membro',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                for (final subscription in active)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '• ${plansById[subscription.planId]?.name ?? subscription.planId} '
                      '(${subscription.activeServiceIds.map((id) => servicesById[id]?.name ?? id).join(', ')})',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
