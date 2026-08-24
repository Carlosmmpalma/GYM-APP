import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/member_summary.dart';
import 'assessment_list_screen.dart';
import 'member_stats_screen.dart';
import 'training_plan_editor_screen.dart';
import 'workout_history_screen.dart';
import '../widgets/start_workout_button.dart';

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
          // Estatísticas antes do histórico: o histórico responde "o que
          // fez no dia 12", as estatísticas respondem "como é que ele
          // está" — e é essa a pergunta que se faz antes de falar com
          // o aluno.
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Estatísticas'),
              subtitle: const Text(
                'Consistência, força e composição corporal',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemberStatsScreen(member: member),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Treinos feitos'),
              subtitle: const Text(
                'O que foi feito em cada sessão, série a série',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkoutHistoryScreen(
                    memberId: member.uid,
                    title: 'Treinos — ${member.name}',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Fase 11 — num ginásio com acompanhamento, o instrutor
          // regista o treino ao lado do aluno. É o mesmo componente que
          // o aluno usa; o que muda é o `performedBy` que fica no
          // registo.
          StartWorkoutButton(memberId: member.uid),
          const SizedBox(height: 16),
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
