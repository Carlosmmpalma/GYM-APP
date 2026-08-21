import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../widgets/design_system.dart';
import 'plan_detail_screen.dart';

/// UC26 — Ecrã Gestor: criar/editar Plans e Services (Fase 3).
///
/// Versão mínima do guia: lista os Plans do tenant, permite criar um
/// novo (nome/descrição/preço/moeda), e abre [PlanDetailScreen] para
/// editar os detalhes e gerir os Services associados. Não faz validação
/// de permissões aqui — isso é responsabilidade de quem navega para
/// este ecrã (só managers, ver `home_screen.dart`) e das Security
/// Rules (`firestore.rules`), que são a fonte de verdade real.
class ManagePlansScreen extends ConsumerWidget {
  const ManagePlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansProvider);
    final hasServices =
        (ref.watch(servicesProvider).valueOrNull ?? const []).isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Planos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPlan(context, ref),
        tooltip: 'Novo plano',
        child: const Icon(Icons.add),
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (plans) {
          if (plans.isEmpty) {
            return EmptyState(
              icon: Icons.card_membership_outlined,
              title: 'Ainda não há planos',
              message: 'Um plano é o que o aluno subscreve. Define o preço '
                  'e a que serviços dá acesso, com quantas sessões por '
                  'semana em cada um.',
              // Criar um plano antes de existirem serviços dá um plano
              // que não dá acesso a nada — dizemo-lo aqui em vez de
              // deixar descobrir mais tarde no ecrã de detalhe.
              prerequisite: hasServices
                  ? null
                  : 'Cria primeiro os serviços (Gestão › Serviços): um '
                      'plano sem serviços não dá acesso a nada.',
              actionLabel: 'Criar o primeiro plano',
              onAction: () => _createPlan(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final plan = plans[index];
              return Card(
                child: ListTile(
                  title: Text(plan.name),
                  subtitle: Text(
                    '${plan.currentPrice.toStringAsFixed(2)} ${plan.currency}'
                    '${plan.active ? '' : ' · inativo'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlanDetailScreen(plan: plan),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createPlan(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_NewPlanData>(
      context: context,
      builder: (_) => const _CreatePlanDialog(),
    );
    if (result == null) return;

    // Sem isto, uma falha na escrita (ex.: Security Rules a negar por
    // não seres Manager do tenant) ficava completamente silenciosa —
    // nada acontecia, sem nenhuma pista do porquê. Mostra o erro real
    // devolvido pelo Firestore, não uma mensagem genérica, porque neste
    // ecrã de diagnóstico é mais importante veres a causa exata do que
    // teres uma frase bonita.
    try {
      await ref.read(planRepositoryProvider).createPlan(
            name: result.name,
            description: result.description,
            currentPrice: result.price,
            currency: result.currency,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar o plano: $e')),
      );
    }
  }
}

class _NewPlanData {
  const _NewPlanData({
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
  });

  final String name;
  final String description;
  final double price;
  final String currency;
}

class _CreatePlanDialog extends StatefulWidget {
  const _CreatePlanDialog();

  @override
  State<_CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends State<_CreatePlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _currencyController = TextEditingController(text: 'EUR');

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _NewPlanData(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.replaceAll(',', '.')),
        currency: _currencyController.text.trim().toUpperCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo plano'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Preço atual'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Obrigatório';
                return double.tryParse(v.replaceAll(',', '.')) == null
                    ? 'Valor inválido'
                    : null;
              },
            ),
            TextFormField(
              controller: _currencyController,
              decoration: const InputDecoration(labelText: 'Moeda (ex: EUR)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Criar')),
      ],
    );
  }
}
