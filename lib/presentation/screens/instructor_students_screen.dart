import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../core/utils/search_text.dart';
import '../../domain/entities/member_summary.dart';
import '../widgets/design_system.dart';
import 'student_training_screen.dart';

/// Fase 8 — "Alunos": ponto de entrada do Instrutor para UC13/UC14/UC16
/// (mockup: `<b>Alunos</b>Ponto de entrada para UC13/UC14/UC16`).
/// O destino ao tocar é o que o distingue do ecrã do Gestor:
/// `ManageMembersScreen` vai para `MemberDetailScreen` (subscrições);
/// este vai para `StudentTrainingScreen` (plano de treino + avaliações),
/// um conceito diferente.
///
/// Reutilizava `membersProvider` — e com ele listava TODOS os alunos
/// ativos do estúdio, incluindo quem não treina nada que este instrutor
/// lecione. Passou a `visibleMembersProvider`.
class InstructorStudentsScreen extends ConsumerStatefulWidget {
  const InstructorStudentsScreen({super.key});

  @override
  ConsumerState<InstructorStudentsScreen> createState() =>
      _InstructorStudentsScreenState();
}

class _InstructorStudentsScreenState
    extends ConsumerState<InstructorStudentsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    // `visibleMembersProvider` e não `membersProvider`: um Instrutor
    // via TODOS os alunos ativos do estúdio, incluindo os que não
    // treinam nada que ele lecione. Ver a nota nesse provider sobre
    // isto ser âmbito e não segurança.
    final membersAsync = ref.watch(visibleMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alunos')),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (members) {
          final active = members.where((m) => m.active).toList();
          if (active.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Sem alunos ativos',
              message: 'A partir daqui abres o treino de cada aluno: '
                  'avaliações, plano de treino e evolução de carga. Só '
                  'aparecem membros ativos.',
            );
          }
          // Sem filtro de estado aqui: o ecrã já só mostra ativos, e um
          // Instrutor não tem nada a fazer com a ficha de quem saiu.
          final visible = active
              .where((m) => searchMatchesAny([m.name, m.memberNumber], _query))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SearchField(
                  hintText: 'Procurar aluno',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (visible.isEmpty)
                Expanded(
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'Nada encontrado',
                    message: 'Nenhum aluno corresponde a "$_query".',
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

  Widget _buildList(List<MemberSummary> active) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
  }
}
