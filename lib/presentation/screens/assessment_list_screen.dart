import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/member_summary.dart';
import 'assessment_detail_screen.dart';

final _dateFormat = DateFormat('d MMM yyyy', 'pt_PT');

/// Fase 8 (UC04) — "lista, mais recente primeiro". Usado por
/// Instrutor/Gestor (a partir de `StudentTrainingScreen`) E pelo
/// próprio Aluno (a partir do seu perfil) — o mesmo ecrã, o que muda é
/// só quem consegue chegar a ele (Security Rules) e se aparece um
/// botão de criar (nunca aparece para o Aluno, só lê).
class AssessmentListScreen extends ConsumerWidget {
  const AssessmentListScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessmentsAsync = ref.watch(assessmentsProvider(member.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('Avaliações')),
      body: assessmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (assessments) {
          if (assessments.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não existe nenhuma avaliação.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: assessments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final assessment = assessments[index];
              return Card(
                child: ListTile(
                  title: Text(_dateFormat.format(assessment.createdAt)),
                  subtitle: Text(
                    'Peso ${assessment.peso}kg · IMC ${assessment.imc.toStringAsFixed(1)}'
                    '${assessment.wasEdited ? ' · editada' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AssessmentDetailScreen(
                          member: member, assessment: assessment),
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
