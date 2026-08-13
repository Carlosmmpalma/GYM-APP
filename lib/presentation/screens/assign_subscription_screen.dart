import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
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
class AssignSubscriptionScreen extends ConsumerStatefulWidget {
  const AssignSubscriptionScreen({super.key});

  @override
  ConsumerState<AssignSubscriptionScreen> createState() =>
      _AssignSubscriptionScreenState();
}

class _AssignSubscriptionScreenState
    extends ConsumerState<AssignSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();

  MemberSummary? _member;
  Plan? _plan;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final plansAsync = ref.watch(plansProvider);

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
              const SizedBox(height: 16),
              plansAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Erro a carregar planos: $error'),
                data: (plans) => DropdownButtonFormField<Plan>(
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
        const SnackBar(content: Text('Plano atribuído com sucesso.')),
      );
      Navigator.of(context).pop();
    } on SubscriptionServiceConflictException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      setState(() => _errorMessage = 'Não foi possível atribuir o plano: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
