import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/subscription.dart';
import '../../repositories/usage_repository.dart';
import 'assign_subscription_screen.dart';

/// Um serviço ao qual uma subscription dá acesso, já resolvido (id +
/// nome) — usado só para o picker de "Recalcular utilização" abaixo
/// (task #63, fora do plano de fases: `recalculateUsage.ts` existia
/// desde a Fase 4 mas não tinha nenhuma UI a chamá-lo).
typedef _ServiceEntry = ({String id, String name});

/// Detalhe de um membro: todas as subscriptions (ativas E histórico —
/// ao contrário da secção inline em `AssignSubscriptionScreen`, que só
/// mostra ativas), com o Plano/Services resolvidos por nome. Pedido
/// pelo Carlos depois de testar a Fase 3 ("ver os planos de cada
/// utilizador") — não está atribuído a nenhuma fase do guia.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionsAsync = ref.watch(memberSubscriptionsProvider(member.uid));
    final plansAsync = ref.watch(plansProvider);
    final servicesAsync = ref.watch(servicesProvider);
    // Mesmo raciocínio de `currentPlan` em `plan_detail_screen.dart`:
    // `member` é a cópia imutável de quando `ManageMembersScreen`
    // construiu este ecrã — resolve pelo `membersProvider` ao vivo para
    // o toggle de ativo/inativo refletir o valor real.
    final currentMember = ref.watch(membersProvider).valueOrNull?.firstWhere(
              (m) => m.uid == member.uid,
              orElse: () => member,
            ) ??
        member;

    return Scaffold(
      appBar: AppBar(title: Text(currentMember.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AssignSubscriptionScreen(initialMember: member),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Atribuir novo plano'),
      ),
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
                    'Nº de sócio: ${currentMember.memberNumber}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Desativar, nunca eliminar — o uid continua referenciado
          // por subscriptions/bookings já feitos; apagar a conta
          // partiria esse histórico. Escreve `status` (Firestore),
          // não mexe na conta do Firebase Auth (login continua a
          // funcionar; é uma decisão de negócio, não bloqueio técnico
          // de acesso — Rules/login mais fino fica para quando for
          // pedido).
          Card(
            child: SwitchListTile(
              title: const Text('Membro ativo'),
              subtitle: Text(
                currentMember.active
                    ? 'Pode continuar a marcar-se e a receber planos novos.'
                    : 'Inativo — mantém o histórico, mas devias evitar '
                        'atribuir-lhe novos planos.',
              ),
              value: currentMember.active,
              onChanged: (value) async {
                try {
                  await ref.read(memberRepositoryProvider).setMemberActive(
                        memberId: currentMember.uid,
                        active: value,
                      );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Não foi possível atualizar o membro: $e')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('Planos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Text('Erro: $error'),
            data: (plans) => servicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text('Erro: $error'),
              data: (services) => subscriptionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Erro: $error'),
                data: (subscriptions) {
                  if (subscriptions.isEmpty) {
                    return const Text(
                      'Este membro ainda não teve nenhum plano atribuído.',
                    );
                  }
                  // Mais recente primeiro — startDate é o único campo
                  // temporal garantido em todas (endDate é opcional).
                  final sorted = [...subscriptions]
                    ..sort((a, b) => b.startDate.compareTo(a.startDate));
                  final plansById = {for (final p in plans) p.id: p};
                  final servicesById = {for (final s in services) s.id: s};
                  return Column(
                    children: sorted
                        .map(
                          (subscription) => _SubscriptionTile(
                            subscription: subscription,
                            plan: plansById[subscription.planId],
                            services: subscription.activeServiceIds
                                .map((id) => servicesById[id]?.name ?? id)
                                .toList(),
                            // Só entram serviços que ainda existem como
                            // doc `services/{id}` — no domínio atual
                            // isso é sempre o caso (nunca se elimina um
                            // Service, só desativa), mas evita um crash
                            // hipotético no picker se algum dia deixar
                            // de ser verdade.
                            recalculableServices: subscription.activeServiceIds
                                .where(servicesById.containsKey)
                                .map((id) => (id: id, name: servicesById[id]!.name))
                                .toList(),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
          ),
          // Espaço para o FAB não tapar o último cartão.
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerStatefulWidget {
  const _SubscriptionTile({
    required this.subscription,
    required this.plan,
    required this.services,
    required this.recalculableServices,
  });

  final Subscription subscription;
  final Plan? plan;
  final List<String> services;
  final List<_ServiceEntry> recalculableServices;

  @override
  ConsumerState<_SubscriptionTile> createState() => _SubscriptionTileState();
}

class _SubscriptionTileState extends ConsumerState<_SubscriptionTile> {
  bool _recalculating = false;

  /// Task #63 — `recalculateUsage.ts` existe desde a Fase 4 mas nunca
  /// teve nenhuma UI a chamá-lo; era uma Cloud Function invocável "às
  /// cegas". Ferramenta de operação do Gestor: reconstrói o read model
  /// `usage/{...}` a partir dos bookings reais deste membro+serviço —
  /// útil, por exemplo, depois de um cancelamento manual direto no
  /// Firestore (fora da app) ou para confirmar que a barra "X/Y esta
  /// semana" do aluno está correta.
  Future<void> _recalculate(BuildContext context) async {
    final entries = widget.recalculableServices;
    if (entries.isEmpty) return;

    _ServiceEntry? chosen = entries.length == 1 ? entries.first : null;
    chosen ??= await showDialog<_ServiceEntry>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Recalcular utilização de que serviço?'),
        children: entries
            .map(
              (entry) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(entry),
                child: Text(entry.name),
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null || !mounted) return;
    final target = chosen;

    // `_recalculating` só cobre a chamada de rede (o spinner do botão),
    // nunca o tempo em que o diálogo de resultado fica aberto — um
    // `CircularProgressIndicator` indeterminado ainda a animar por
    // baixo do diálogo faz o `pumpAndSettle()` do teste nunca
    // estabilizar (bug real apanhado por um `flutter test` a sério,
    // não pelo balanço de chavetas). Por isso a chamada + o `setState`
    // que a desliga ficam isolados do `showDialog` abaixo.
    setState(() => _recalculating = true);
    List<UsageRecalculationEntry> result;
    try {
      result = await ref.read(usageRepositoryProvider).recalculateUsage(
            memberId: widget.subscription.memberId,
            serviceId: target.id,
          );
    } catch (e) {
      if (mounted) setState(() => _recalculating = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível recalcular: $e')),
      );
      return;
    }
    if (mounted) setState(() => _recalculating = false);
    if (!context.mounted) return;

    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nada para recalcular — este membro nunca teve marcações de '
            '${target.name}.',
          ),
        ),
      );
      return;
    }

    final sorted = [...result]..sort((a, b) => a.period.compareTo(b.period));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Utilização recalculada — ${target.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sorted
                .map((e) => Text('${e.period}: ${e.used} sessão(ões)'))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context) {
    switch (widget.subscription.status) {
      case SubscriptionStatus.active:
        return Colors.green;
      case SubscriptionStatus.paused:
        return Colors.orange;
      case SubscriptionStatus.cancelled:
      case SubscriptionStatus.expired:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _statusLabel() {
    switch (widget.subscription.status) {
      case SubscriptionStatus.active:
        return 'Ativo';
      case SubscriptionStatus.paused:
        return 'Em pausa';
      case SubscriptionStatus.cancelled:
        return 'Cancelado';
      case SubscriptionStatus.expired:
        return 'Expirado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = widget.subscription;
    final plan = widget.plan;
    final services = widget.services;
    final dateFormat = DateFormat('d MMM yyyy', 'pt_PT');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan?.name ?? subscription.planId,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Chip(
                  label: Text(_statusLabel()),
                  backgroundColor: _statusColor(context).withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: _statusColor(context)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Serviços: ${services.isEmpty ? '—' : services.join(', ')}'),
            const SizedBox(height: 4),
            Text(
              '${subscription.agreedPrice.toStringAsFixed(2)} ${subscription.currency} '
              '· desde ${dateFormat.format(subscription.startDate)}'
              '${subscription.endDate != null ? ' até ${dateFormat.format(subscription.endDate!)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.recalculableServices.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _recalculating ? null : () => _recalculate(context),
                  icon: _recalculating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('Recalcular utilização'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
