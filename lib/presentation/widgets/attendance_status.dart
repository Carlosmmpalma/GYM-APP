import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/attendance.dart';
import '../../domain/entities/session_occurrence.dart';
import 'design_system.dart';

/// O estado da chamada de uma aula, para quem está a olhar para uma
/// LISTA de aulas.
///
/// ## A pergunta que isto responde
///
/// "Já marquei a chamada desta aula?" — e responde-a **sem abrir a
/// aula**. Antes, o cartão de cada aula mostrava "8/12 inscritos", que
/// é lotação, não presença. Um instrutor com quatro aulas num dia que
/// se esqueceu de uma tinha de abrir as quatro para descobrir qual.
///
/// ## Porque não aparece antes de a aula começar
///
/// Uma aula que ainda não aconteceu tem sempre toda a gente por marcar,
/// e isso não é um problema — é o estado normal. Um aviso que está
/// aceso o dia inteiro para todas as aulas de logo à noite deixa de ser
/// lido, e leva o aviso verdadeiro atrás dele.
class AttendanceBadge extends ConsumerWidget {
  const AttendanceBadge({super.key, required this.occurrence});

  final SessionOccurrence occurrence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (occurrence.status != SessionOccurrenceStatus.scheduled) {
      return const SizedBox.shrink();
    }
    if (DateTime.now().isBefore(occurrence.startAt)) {
      return const SizedBox.shrink();
    }

    final registos = ref.watch(occurrenceAttendanceProvider(occurrence.id));
    // Enquanto carrega não se diz nada. Mostrar "0 por marcar" durante
    // meio segundo e só depois corrigir para "3 por marcar" é pior do
    // que não mostrar — o primeiro número é o que fica lido.
    final lista = registos.valueOrNull;
    if (lista == null) return const SizedBox.shrink();

    final resumo = AttendanceSummary.de(
      lista,
      inscritos: occurrence.activeBookingCount,
    );
    if (resumo.vazia) return const SizedBox.shrink();

    if (resumo.completa) {
      return const Pill('Chamada feita', tone: PillTone.ok);
    }
    return Pill(
      resumo.porMarcar == 1 ? '1 por marcar' : '${resumo.porMarcar} por marcar',
      tone: PillTone.warn,
    );
  }
}

/// Os três números da chamada: presentes, faltas, por marcar.
///
/// ## Porque faltava
///
/// O ecrã da aula já tinha o botão certo — "marcar os restantes como
/// presentes" — e uma frase, "Presenças registadas para todos", quando
/// não havia restantes. O que não tinha era a **contagem**: quantos
/// vieram, quantos faltaram, quantos ainda não foram vistos.
///
/// É a diferença entre saber que há trabalho por fazer e saber quanto.
/// Um instrutor a olhar para uma turma de doze quer o número antes dos
/// nomes; os nomes são o passo seguinte, e só para quem falta.
class AttendanceCounts extends StatelessWidget {
  const AttendanceCounts({
    super.key,
    required this.resumo,
    required this.comecou,
  });

  final AttendanceSummary resumo;

  /// Antes de a aula começar, "por marcar" é o estado normal e não um
  /// aviso — fica neutro em vez de laranja. Um aviso aceso desde a
  /// manhã para a aula das nove da noite ensina a ignorá-lo.
  final bool comecou;

  @override
  Widget build(BuildContext context) {
    if (resumo.vazia) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Pill('${resumo.presentes} presentes', tone: PillTone.ok),
          if (resumo.faltas > 0)
            Pill('${resumo.faltas} faltas', tone: PillTone.danger),
          if (resumo.porMarcar > 0)
            Pill(
              '${resumo.porMarcar} por marcar',
              tone: comecou ? PillTone.warn : PillTone.neutral,
            ),
        ],
      ),
    );
  }
}

/// O estado de UM inscrito, à cabeça da linha.
///
/// ## Porque é um ícone à esquerda e não duas cores à direita
///
/// Estavam dois `IconButton` no fim da linha — um visto e uma cruz —
/// sempre os dois visíveis, ambos cinzentos enquanto não houvesse
/// registo. Para encontrar quem faltava marcar numa turma de doze era
/// preciso ler a cor de vinte e quatro ícones pequenos, e "ainda não
/// marcado" era exatamente igual a "marcado" a um metro de distância.
///
/// À cabeça da linha, os estados formam uma coluna que se lê de cima a
/// baixo de uma vez: ○ ✓ ✓ ○ ✓. É isso que torna a pergunta "falta
/// alguém?" respondível sem ler nomes.
///
/// ## E porque o estado também está escrito
///
/// A palavra aparece no subtítulo da linha, não só a cor do ícone. Cor
/// sozinha não é informação para quem não distingue verde de vermelho —
/// e são precisamente o verde e o vermelho que esta app usaria.
class AttendanceMark extends StatelessWidget {
  const AttendanceMark({super.key, required this.status});

  /// `null` = ainda sem registo.
  final AttendanceStatus? status;

  static String rotulo(AttendanceStatus? status) => switch (status) {
        AttendanceStatus.attended => 'Presente',
        AttendanceStatus.noShow => 'Faltou',
        null => 'Por marcar',
      };

  @override
  Widget build(BuildContext context) {
    final (icone, cor) = switch (status) {
      AttendanceStatus.attended => (Icons.check_circle, AppColors.ok),
      AttendanceStatus.noShow => (Icons.cancel, AppColors.red),
      // Um círculo VAZIO, não um visto apagado: um visto cinzento
      // continua a ler-se como um visto, e era metade do problema.
      null => (Icons.radio_button_unchecked, AppColors.dim),
    };
    return Icon(icone, color: cor, semanticLabel: rotulo(status));
  }
}
