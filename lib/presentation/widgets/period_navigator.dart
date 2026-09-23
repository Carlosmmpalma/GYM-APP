import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _formatoSemana = DateFormat('d MMM', 'pt_PT');

/// "‹  setembro de 2026  ›" — o cabeçalho de quem navega por períodos.
///
/// ## Porque é um widget e não quatro cópias
///
/// Estava escrito à mão em [FreeTrainingScreen],
/// [InstructorCalendarScreen], [ManageFreeTrainingScreen] (por semanas) e
/// [ManagePaymentsScreen] (por meses) — igual até ao espaçamento, e com
/// o mesmo defeito nos quatro: um [Row] centrado com dois [IconButton] e
/// um [Text] sem constrangimento nenhum.
///
/// Os dois botões ocupam 96 px fixos — são ícones, não encolhem — e o
/// texto pedia a largura que quisesse. Com o tamanho de letra do sistema
/// a 1.3× faltavam 54 px num Android de 360; a 2.0×, faltavam 207. As
/// setas de mudar de período ficavam fora do ecrã, e o ecrã passava a
/// mostrar um período só — sem nada a indicar que havia mais.
///
/// Encontrei três cópias, corrigi-as, e a matriz de ecrãs apontou logo
/// a quarta. É o argumento todo para extrair: a quinta vai nascer certa.
class PeriodNavigator extends StatelessWidget {
  const PeriodNavigator({
    super.key,
    required this.label,
    required this.onAnterior,
    required this.onSeguinte,
    this.tooltipAnterior = 'Período anterior',
    this.tooltipSeguinte = 'Período seguinte',
  });

  final String label;

  /// `null` desativa o botão — há períodos sem "seguinte" (não se marcam
  /// mensalidades do futuro).
  final VoidCallback? onAnterior;
  final VoidCallback? onSeguinte;

  final String tooltipAnterior;
  final String tooltipSeguinte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: tooltipAnterior,
          icon: const Icon(Icons.chevron_left),
          onPressed: onAnterior,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            // Com texto muito grande, um período abreviado continua a
            // dizer qual é; um botão fora do ecrã não tem remédio
            // nenhum. É por isso que é o texto que cede.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: tooltipSeguinte,
          icon: const Icon(Icons.chevron_right),
          onPressed: onSeguinte,
        ),
      ],
    );
  }
}

/// O [PeriodNavigator] com o intervalo de uma semana já formatado.
class WeekNavigator extends StatelessWidget {
  const WeekNavigator({
    super.key,
    required this.inicio,
    required this.fim,
    required this.onAnterior,
    required this.onSeguinte,
  });

  final DateTime inicio;
  final DateTime fim;
  final VoidCallback onAnterior;

  /// `null` desativa a seta — há semanas sem "seguinte" (o horizonte de
  /// marcação do aluno acaba algures).
  final VoidCallback? onSeguinte;

  @override
  Widget build(BuildContext context) {
    return PeriodNavigator(
      label: '${_formatoSemana.format(inicio)} – '
          '${_formatoSemana.format(fim)}',
      onAnterior: onAnterior,
      onSeguinte: onSeguinte,
      tooltipAnterior: 'Semana anterior',
      tooltipSeguinte: 'Semana seguinte',
    );
  }
}
