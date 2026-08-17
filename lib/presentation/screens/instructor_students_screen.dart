import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import 'student_training_screen.dart';

/// Fase 8 — "Alunos": ponto de entrada do Instrutor para UC13/UC14/UC16
/// (mockup: `<b>Alunos</b>Ponto de entrada para UC13/UC14/UC16`).
/// Reutiliza `membersProvider` (já existia desde a Fase 3, usado pelo
/// Gestor) — os dados são os mesmos, só o destino ao tocar muda:
/// `ManageMembersScreen` (Gestor) vai para `MemberDetailScreen`
/// (subscriptions); este vai para `StudentTrainingScreen` (plano de
/// treino + avaliações), um conceito diferente.
class InstructorStudentsScreen extends ConsumerWidget {
  const InstructorStudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alunos')),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (members) {
          final active = members.where((m) => m.active).toList();
          if (active.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ainda não existe nenhum aluno ativo.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: active.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = active[index];
              return Card(
                child: ListTile(
                  title: Text(member.name),
                  subtitle: Text('Nº ${member.memberNumber}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StudentTrainingScreen(member: member),
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
