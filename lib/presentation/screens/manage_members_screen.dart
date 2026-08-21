import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../core/utils/search_text.dart';
import '../../domain/entities/member_summary.dart';
import '../widgets/design_system.dart';
import 'create_user_screen.dart';
import 'member_detail_screen.dart';

/// Ecrã Gestor: lista de membros do tenant, ponto de entrada para
/// `MemberDetailScreen` (ver os planos/subscriptions de cada um —
/// pedido pelo Carlos depois de testar a Fase 3, não estava atribuído
/// a nenhuma fase do guia) e para `CreateUserScreen` (o "+" — UC22,
/// gap encontrado a comparar com os mockups: faltava desde a Fase 1).
class ManageMembersScreen extends ConsumerStatefulWidget {
  const ManageMembersScreen({super.key});

  @override
  ConsumerState<ManageMembersScreen> createState() =>
      _ManageMembersScreenState();
}

class _ManageMembersScreenState extends ConsumerState<ManageMembersScreen> {
  String _query = '';

  /// `null` = todos. Um ginásio com centenas de inscritos tem sempre
  /// inativos pelo meio, e a pergunta "quem está ativo hoje" é a mais
  /// frequente — mas abrir já filtrado esconderia gente sem ninguém
  /// pedir.
  bool? _activeFilter;

  @override
  Widget build(BuildContext context) {
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
        error: (error, stack) => ErrorState(error: error),
        data: (members) {
          if (members.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline,
              title: 'Ainda não há membros',
              message: 'Os membros são as pessoas inscritas no ginásio. '
                  'Criar um membro dá-lhe um nº de sócio e acesso à app; '
                  'a partir daí podes atribuir-lhe um plano.',
              actionLabel: 'Criar o primeiro membro',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateUserScreen()),
              ),
            );
          }
          final activeCount = members.where((m) => m.active).length;
          final visible = members.where((member) {
            if (_activeFilter != null && member.active != _activeFilter) {
              return false;
            }
            // Nome OU número: quem procura não deve ter de escolher
            // antes qual dos dois vai escrever.
            return searchMatchesAny(
              [member.name, member.memberNumber],
              _query,
            );
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    SearchField(
                      hintText: 'Procurar por nome ou nº de sócio',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 10),
                    FilterChipsRow<bool>(
                      allCount: members.length,
                      selected: _activeFilter,
                      onSelected: (value) =>
                          setState(() => _activeFilter = value),
                      options: [
                        (true, 'Ativos', activeCount),
                        (false, 'Inativos', members.length - activeCount),
                      ],
                    ),
                  ],
                ),
              ),
              if (visible.isEmpty)
                Expanded(
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'Nada encontrado',
                    message: _query.isEmpty
                        ? 'Não há membros neste estado.'
                        : 'Nenhum membro corresponde a "$_query".',
                  ),
                )
              else
                Expanded(child: _buildList(visible)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<MemberSummary> members) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
  }
}
