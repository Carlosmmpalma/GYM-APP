import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import 'create_user_screen.dart';
import 'member_detail_screen.dart';

/// Ecrã Gestor: lista de membros do tenant, ponto de entrada para
/// `MemberDetailScreen` (ver os planos/subscriptions de cada um —
/// pedido pelo Carlos depois de testar a Fase 3, não estava atribuído
/// a nenhuma fase do guia) e para `CreateUserScreen` (o "+" — UC22,
/// gap encontrado a comparar com os mockups: faltava desde a Fase 1).
class ManageMembersScreen extends ConsumerWidget {
  const ManageMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Membros')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateUserScreen()),
        ),
        tooltip: 'Criar utilizador',
        child: const Icon(Icons.add),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (members) {
          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não existe nenhum membro. Usa o botão "+" para '
                  'criar o primeiro.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = members[index];
              return Card(
                child: ListTile(
                  title: Text(member.name),
                  subtitle: Text(
                    'Nº ${member.memberNumber}'
                    '${member.active ? '' : ' · inativo'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemberDetailScreen(member: member),
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
}
