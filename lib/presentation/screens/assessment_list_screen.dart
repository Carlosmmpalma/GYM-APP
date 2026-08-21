import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../widgets/design_system.dart';
import 'assessment_detail_screen.dart';
import 'assessment_form_screen.dart';

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
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;

    // Fase 11 — "Nova avaliação" vivia no ecrã de CIMA, ao lado dos
    // cartões "Plano de treino" e "Avaliações". Criar uma avaliação
    // pertence a onde se veem as avaliações: é aí que se percebe se já
    // há uma deste mês, e é aí que se está quando a vontade aparece.
    //
    // Nunca para o Aluno: ele lê o seu histórico, não se avalia a si
    // próprio. Era o que a documentação desta classe já dizia — só que
    // o botão nunca chegou a existir aqui.
    final canCreate =
        appUser != null && (appUser.isInstructor || appUser.isManager);

    // As Security Rules recusam escrever uma avaliação sem o
    // consentimento do membro para dados de saúde (RGPD, artigo 9.º).
    // Mostrar o botão nesse caso seria oferecer um caminho que termina
    // numa recusa do servidor.
    final profile = ref.watch(memberProfileProvider(member.uid)).valueOrNull;
    final hasConsent = profile?.consent.healthDataGranted ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Avaliações')),
      floatingActionButton: canCreate && hasConsent
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AssessmentFormScreen(member: member),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nova avaliação'),
            )
          : null,
      body: assessmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (assessments) {
          if (canCreate && !hasConsent) {
            return EmptyState(
              icon: Icons.lock_outline,
              title: 'Sem autorização para avaliações',
              message: '${member.name} não autorizou o tratamento de dados '
                  'de saúde, por isso não podem ser registadas avaliações '
                  'físicas. É uma escolha dele, que pode mudar a qualquer '
                  'momento no perfil.',
              prerequisite: 'O servidor recusa a escrita mesmo que a app '
                  'a permitisse — não é uma limitação do ecrã.',
            );
          }

          if (assessments.isEmpty) {
            return EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'Sem avaliações',
              message: canCreate
                  ? 'As avaliações registam medidas e composição corporal '
                      'ao longo do tempo, para acompanhar a evolução.'
                  : 'As avaliações registam medidas e composição corporal '
                      'ao longo do tempo. Assim que o instrutor fizer a '
                      'primeira, aparece aqui o histórico.',
              actionLabel: canCreate ? 'Fazer a primeira avaliação' : null,
              onAction: canCreate
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AssessmentFormScreen(member: member),
                        ),
                      )
                  : null,
            );
          }
          return ListView.separated(
            // Espaço para o botão flutuante não tapar a última linha.
            padding: EdgeInsets.fromLTRB(16, 16, 16, canCreate ? 88 : 16),
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
