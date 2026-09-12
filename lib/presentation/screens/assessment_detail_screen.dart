import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/assessment.dart';
import '../../domain/entities/member_summary.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firebase_error_text.dart';
import 'assessment_form_screen.dart';
import '../widgets/catalogue_delete.dart';

final _dateFormat = DateFormat('d MMM yyyy', 'pt_PT');

/// Fase 8 (UC04/UC14) — "Detalhe da avaliação": os 17 campos, sem
/// exceção, em leitura. "Editar" só para Instrutor/Gestor (UC04/UC14
/// fechado) — um Aluno chega aqui também (lê a própria), mas nunca vê
/// o botão.
class AssessmentDetailScreen extends ConsumerWidget {
  const AssessmentDetailScreen(
      {super.key, required this.member, required this.assessment});

  final MemberSummary member;
  final Assessment assessment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final canEdit =
        (appUser?.isManager ?? false) || (appUser?.isInstructor ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_dateFormat.format(assessment.createdAt)),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AssessmentFormScreen(
                      member: member, assessment: assessment),
                ),
              ),
            ),
          if (canEdit)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(member.name, style: Theme.of(context).textTheme.titleMedium),
          if (assessment.wasEdited) ...[
            const SizedBox(height: 4),
            Text(
              'Editada em ${_dateFormat.format(assessment.updatedAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          _section(context, 'Composição corporal', [
            _row('Idade', '${assessment.idade}'),
            _row('Peso', '${assessment.peso} kg'),
            _row('Altura', '${assessment.altura} m'),
            _row('IMC', assessment.imc.toStringAsFixed(1)),
            _row('% Massa Gorda', '${assessment.percentMassaGorda}%'),
            _row('Massa Muscular', '${assessment.massaMuscular} kg'),
            _row('Gordura Visceral', '${assessment.gorduraVisceral}'),
            _row('Metabolismo Basal', '${assessment.metabolismoBasal} kcal'),
            _row('% Água', '${assessment.percentAgua}%'),
            _row('Idade Metabólica', '${assessment.idadeMetabolica}'),
          ]),
          _section(context, 'Saúde', [
            _row('Pressão Arterial', assessment.pressaoArterial),
            _row('Perímetro Cintura', '${assessment.perimetroCintura} cm'),
            _row('Perímetro Abdominal', '${assessment.perimetroAbdominal} cm'),
          ]),
          _section(context, 'Físicos', [
            _row('Força MS', assessment.forcaMS),
            _row('Força MI', assessment.forcaMI),
            _row('Força Core', assessment.forcaCore),
            _row('Flexibilidade', assessment.flexibilidade),
            _row('Resistência', assessment.resistencia),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      // Uma linha etiqueta/valor com `spaceBetween` e dois `Text` sem
      // constrangimento nenhum. Etiquetas como "Percentagem de massa
      // gorda" ou "Perímetro abdominal" passavam a largura de TODOS os
      // telemóveis — 23 px num Pixel 7 e 75 num Android de 360, já com
      // o tamanho de letra normal.
      //
      // Os dois lados cedem, mas de formas diferentes. A etiqueta
      // quebra em linhas (`Expanded`, que fica com o que sobrar). O
      // valor também quebra — a 2.0× um valor sozinho chega a ocupar a
      // largura toda — mas **nunca é cortado**: um peso com o fim
      // truncado não é informação incompleta, é outro número, e num
      // ecrã de avaliação física isso lê-se e acredita-se.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.mute)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// Uma avaliação lançada no aluno errado não é histórico de nada — é
  /// um engano, e nenhum outro documento aponta para ela.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Eliminar esta avaliação?',
      consequence: 'As medidas desta data desaparecem do histórico de '
          '${member.name} e dos gráficos de evolução.',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(assessmentRepositoryProvider).deleteAssessment(
            memberId: member.uid,
            assessmentId: assessment.id,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avaliação eliminada.')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível eliminar. Tenta outra vez.')),
        ),
      );
    }
  }
}
