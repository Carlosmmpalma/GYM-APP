import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/plan_service.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/usage_rule.dart';

/// UC26 — detalhe de um Plan: dados gerais + gestão dos Services
/// incluídos (com a respetiva [UsageRule]). Cada Service do tenant
/// aparece sempre na lista (ativo ou não incluído no Plan); alternar o
/// switch chama `setPlanService(enabled: ...)` — o documento
/// `plans/{id}/services/{serviceId}` é criado/atualizado, nunca
/// apagado (mantém a regra "id do documento == serviceId" simples,
/// ver `plan_service.dart`).
class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({super.key, required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planServicesAsync = ref.watch(planServicesProvider(plan.id));
    // `servicesProvider` (StreamProvider, plan_providers.dart) em vez de
    // um FutureProvider próprio: assim, criar um Service novo em
    // `ManageServicesScreen` aparece aqui sem precisar de nenhum
    // `ref.invalidate()` manual entre ecrãs diferentes. Filtra para
    // ativos aqui, já que `servicesProvider` devolve TODOS.
    final activeServicesAsync = ref.watch(servicesProvider).whenData(
          (services) => services.where((s) => s.active).toList(),
        );

    return Scaffold(
      appBar: AppBar(title: Text(plan.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.currentPrice.toStringAsFixed(2)} ${plan.currency}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (plan.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(plan.description),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Serviços incluídos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          activeServicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Text('Erro: $error'),
            data: (services) => planServicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text('Erro: $error'),
              data: (planServices) {
                if (services.isEmpty) {
                  return const Text(
                    'Ainda não existe nenhum serviço ativo no tenant. Cria um '
                    'em Gestão → Serviços.',
                  );
                }
                final byServiceId = {
                  for (final ps in planServices) ps.serviceId: ps,
                };
                return Column(
                  children: services
                      .map(
                        (service) => _ServiceTile(
                          planId: plan.id,
                          service: service,
                          planService: byServiceId[service.id],
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({
    required this.planId,
    required this.service,
    required this.planService,
  });

  final String planId;
  final Service service;
  final PlanService? planService;

  bool get _enabled => planService?.enabled ?? false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(service.name),
            subtitle: Text(
              _enabled ? (planService?.usage.describe() ?? '') : 'Não incluído',
            ),
            value: _enabled,
            onChanged: (value) => _toggle(context, ref, value),
          ),
          if (_enabled)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _editUsage(context, ref),
                  child: const Text('Editar regra de utilização'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool value) async {
    try {
      if (value) {
        // Ao ativar, pede logo a regra de utilização — sem isto ficaria
        // "enabled: true" sem UsageRule definida, o que não faz sentido.
        final usage = await showDialog<UsageRule>(
          context: context,
          builder: (_) => _UsageRuleDialog(initial: planService?.usage),
        );
        if (usage == null) return;
        await ref.read(planRepositoryProvider).setPlanService(
              planId: planId,
              serviceId: service.id,
              enabled: true,
              usage: usage,
            );
      } else {
        await ref.read(planRepositoryProvider).setPlanService(
              planId: planId,
              serviceId: service.id,
              enabled: false,
              usage: planService?.usage ?? const UsageRule.unlimited(),
            );
      }
      ref.invalidate(planServicesProvider(planId));
    } catch (e) {
      // Ver nota equivalente em manage_plans_screen.dart#_createPlan —
      // sem isto, uma falha na escrita (ex.: Rules) ficava invisível: o
      // switch simplesmente "não fazia nada".
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o serviço: $e')),
      );
    }
  }

  Future<void> _editUsage(BuildContext context, WidgetRef ref) async {
    final usage = await showDialog<UsageRule>(
      context: context,
      builder: (_) => _UsageRuleDialog(initial: planService?.usage),
    );
    if (usage == null) return;
    try {
      await ref.read(planRepositoryProvider).setPlanService(
            planId: planId,
            serviceId: service.id,
            enabled: true,
            usage: usage,
          );
      ref.invalidate(planServicesProvider(planId));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o serviço: $e')),
      );
    }
  }
}

class _UsageRuleDialog extends StatefulWidget {
  const _UsageRuleDialog({this.initial});

  final UsageRule? initial;

  @override
  State<_UsageRuleDialog> createState() => _UsageRuleDialogState();
}

class _UsageRuleDialogState extends State<_UsageRuleDialog> {
  late bool _unlimited = widget.initial?.isUnlimited ?? true;
  late final _limitController = TextEditingController(
    text: widget.initial?.limit?.toString() ?? '',
  );
  late UsagePeriod _period = widget.initial?.period ?? UsagePeriod.week;

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Regra de utilização'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioListTile<bool>(
            title: const Text('Ilimitado'),
            value: true,
            groupValue: _unlimited,
            onChanged: (v) => setState(() => _unlimited = v!),
          ),
          RadioListTile<bool>(
            title: const Text('Limitado'),
            value: false,
            groupValue: _unlimited,
            onChanged: (v) => setState(() => _unlimited = v!),
          ),
          if (!_unlimited) ...[
            TextField(
              controller: _limitController,
              decoration: const InputDecoration(labelText: 'Quantidade'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<UsagePeriod>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Período'),
              items: UsagePeriod.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setState(() => _period = v!),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_unlimited) {
              Navigator.of(context).pop(const UsageRule.unlimited());
              return;
            }
            final limit = int.tryParse(_limitController.text.trim());
            if (limit == null || limit <= 0) return;
            Navigator.of(context)
                .pop(UsageRule.limited(limit: limit, period: _period));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
