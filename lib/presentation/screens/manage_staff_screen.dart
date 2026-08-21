import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../core/utils/search_text.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/staff_summary.dart';
import '../widgets/design_system.dart';
import 'create_user_screen.dart';
import 'staff_detail_screen.dart';

/// Ecrã Gestor: lista de staff (Instrutor/Gestor). Não existia nenhum
/// repository/ecrã para isto antes — só `MemberRepository`/Alunos.
/// Gap encontrado a comparar com `Functional/nxt-studio-screens.html`
/// ("Utilizadores" mistura Alunos e Staff; separei em dois ecrãs para
/// reaproveitar `membersProvider`/`staffProvider` já existentes sem
/// ter de fundir os dois streams).
class ManageStaffScreen extends ConsumerStatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  ConsumerState<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends ConsumerState<ManageStaffScreen> {
  String _query = '';

  /// Filtrar por papel responde a "quem são os meus instrutores?", que
  /// é a pergunta com que se abre este ecrã quase sempre.
  Role? _roleFilter;

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateUserScreen()),
        ),
        tooltip: 'Criar utilizador',
        child: const Icon(Icons.add),
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (staff) {
          if (staff.isEmpty) {
            return EmptyState(
              icon: Icons.badge_outlined,
              title: 'Ainda não há staff',
              message: 'Staff são os Instrutores e Gestores do ginásio. '
                  'Um Instrutor pode dar aulas, marcar presenças e criar '
                  'planos de treino; um Gestor tem acesso a tudo.',
              actionLabel: 'Criar o primeiro staff',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateUserScreen()),
              ),
            );
          }
          final visible = staff.where((person) {
            if (_roleFilter != null && !person.roles.contains(_roleFilter)) {
              return false;
            }
            return searchMatchesAny([person.name, person.email], _query);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    SearchField(
                      hintText: 'Procurar por nome ou email',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 10),
                    FilterChipsRow<Role>(
                      allCount: staff.length,
                      selected: _roleFilter,
                      onSelected: (value) =>
                          setState(() => _roleFilter = value),
                      options: [
                        (
                          Role.instructor,
                          'Instrutores',
                          staff
                              .where((p) => p.roles.contains(Role.instructor))
                              .length,
                        ),
                        (
                          Role.manager,
                          'Gestores',
                          staff
                              .where((p) => p.roles.contains(Role.manager))
                              .length,
                        ),
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
                        ? 'Não há staff com este papel.'
                        : 'Ninguém corresponde a "$_query".',
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

  Widget _buildList(List<StaffSummary> staff) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: staff.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final person = staff[index];
        return Card(
          child: ListTile(
            title: Text(person.name),
            subtitle: Text(
              '${person.roles.map((r) => r.name).join(', ')}'
              '${person.active ? '' : ' · inativo'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StaffDetailScreen(staff: person),
              ),
            ),
          ),
        );
      },
    );
  }
}
