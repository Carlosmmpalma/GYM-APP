import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/member_summary.dart';
import 'assessment_list_screen.dart';
import 'training_plan_editor_screen.dart';

/// Fase 8 — "Ficha do aluno" (mockup): hub do Instrutor para um aluno
/// concreto — plano de treino, histórico de avaliações, e "+ Nova
/// avaliação" em destaque (é a ação mais frequente do dia a dia,
/// mesmo espírito do mockup em pôr isto num botão próprio, não só
/// dentro da lista de avaliações).
class StudentTrainingScreen extends ConsumerWidget {
  const StudentTrainingScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessmentsAsync = ref.watch(assessmentsProvider(member.uid));

    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.fitness_center_outlined),
              title: const Text('Plano de treino'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TrainingPlanEditorScreen(member: member),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text(
                'Avaliações (${assessmentsAsync.valueOrNull?.length ?? 0})',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AssessmentListScreen(member: member),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
