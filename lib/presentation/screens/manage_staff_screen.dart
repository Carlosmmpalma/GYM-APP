import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import 'create_user_screen.dart';
import 'staff_detail_screen.dart';

/// Ecrã Gestor: lista de staff (Instrutor/Gestor). Não existia nenhum
/// repository/ecrã para isto antes — só `MemberRepository`/Alunos.
/// Gap encontrado a comparar com `Functional/nxt-studio-screens.html`
/// ("Utilizadores" mistura Alunos e Staff; separei em dois ecrãs para
/// reaproveitar `membersProvider`/`staffProvider` já existentes sem
/// ter de fundir os dois streams).
class ManageStaffScreen extends ConsumerWidget {
  const ManageStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (staff) {
          if (staff.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não existe nenhum staff. Usa o botão "+" para '
                  'criar o primeiro.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
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
        },
      ),
    );
  }
}
