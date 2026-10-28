import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';

/// A faixa de dias no topo do ecrã de marcação: um toque num dia mostra
/// só as aulas desse dia.
///
/// Existe porque a lista corrida de aulas — duas semanas de horário
/// seguidas, oito quando se pede o completo — era a queixa dos alunos:
/// quem quer a aula de quinta tem de rolar por tudo o que vem antes.
/// Agrupar por dia ajudava a ler, mas não a chegar lá.
///
/// ## O que mostra
///
/// Cada dia é um cartão com o dia da semana, o número, e um ponto se
/// houver aulas. Os dias sem aulas ficam esbatidos mas continuam
/// tocáveis: saltá-los escondia que o estúdio fecha ao domingo, e a
/// pessoa ficava a achar que faltava um dia na faixa.
///
/// "Hoje" aparece por extenso em vez de "qua" — é assim que se fala de
/// treino, e poupa a conta mental de ver "28" e perceber que é hoje.
///
/// [trailing] é para o "ver mais dias" quando o horizonte não está
/// limitado pelo estúdio: vive no fim da faixa, onde a pessoa chega
/// quando já esgotou o que via, e não num botão no fundo de uma lista
/// que deixou de existir.
class DayStrip extends StatefulWidget {
  const DayStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.sessionsPerDay,
    required this.onSelected,
    this.trailing,
  });

  /// Os dias a mostrar, já à meia-noite e por ordem.
  final List<DateTime> days;
  final DateTime selected;

  /// Quantas aulas há em cada dia. Um dia ausente do mapa não tem.
  final Map<DateTime, int> sessionsPerDay;
  final ValueChanged<DateTime> onSelected;
  final Widget? trailing;

  @override
  State<DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<DayStrip> {
  static const _larguraBase = 54.0;
  static const _alturaBase = 78.0;
  static const _espaco = 6.0;
  static const _margem = 16.0;

  /// Quanto o utilizador aumentou o tamanho do texto, limitado a 1,6.
  ///
  /// A faixa tem de crescer com ele. Com altura e largura fixas, o
  /// cartão do dia (três linhas de texto) transbordava assim que o
  /// texto passava de 1,3× — e quem aumenta o texto é, em boa parte,
  /// quem mais precisa de ler isto sem esforço. O limite evita que a
  /// faixa ocupe meio ecrã com o texto no máximo.
  double get _escala =>
      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

  double get _largura => _larguraBase * _escala;

  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // Só depois do primeiro desenho: antes disso o controlador ainda
    // não sabe o tamanho da área visível.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centrar(animar: false));
  }

  @override
  void didUpdateWidget(DayStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _centrar(animar: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Traz o dia escolhido para o meio da faixa.
  ///
  /// Sem isto, escolher "sexta" por um gesto de deslizar na lista (ou
  /// porque o ecrã saltou para o primeiro dia com aulas) deixava o dia
  /// selecionado fora do ecrã — e uma faixa em que não se vê qual está
  /// escolhido não diz nada.
  void _centrar({required bool animar}) {
    if (!_controller.hasClients) return;
    final indice = widget.days.indexOf(widget.selected);
    if (indice < 0) return;

    final centro = _margem + indice * (_largura + _espaco) + _largura / 2;
    final alvo = (centro - _controller.position.viewportDimension / 2)
        .clamp(0.0, _controller.position.maxScrollExtent);

    if (animar) {
      _controller.animateTo(
        alvo,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(alvo);
    }
  }

  /// Avança ou recua uma semana. Só aparece em ecrãs largos, onde não
  /// se arrasta com o dedo: no browser de um computador, uma faixa que
  /// só desliza ao arrastar é uma faixa que não desliza.
  void _passo(int semanas) {
    if (!_controller.hasClients) return;
    final alvo = (_controller.offset + semanas * 7 * (_largura + _espaco))
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      alvo,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);

    return LayoutBuilder(
      builder: (context, caixa) {
        final largo = caixa.maxWidth >= 600;

        final lista = ListView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _margem),
          children: [
            for (final dia in widget.days) ...[
              _DiaChip(
                dia: dia,
                eHoje: dia == hojeDia,
                escolhido: dia == widget.selected,
                aulas: widget.sessionsPerDay[dia] ?? 0,
                largura: _largura,
                onTap: () => widget.onSelected(dia),
              ),
              const SizedBox(width: _espaco),
            ],
            if (widget.trailing != null) widget.trailing!,
          ],
        );

        return SizedBox(
          height: _alturaBase * _escala,
          child: largo
              ? Row(
                  children: [
                    IconButton(
                      tooltip: 'Semana anterior',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _passo(-1),
                    ),
                    Expanded(child: lista),
                    IconButton(
                      tooltip: 'Semana seguinte',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _passo(1),
                    ),
                  ],
                )
              : lista,
        );
      },
    );
  }
}

/// Segunda a domingo, `DateTime.weekday - 1`.
///
/// Fixas e não vindas do `DateFormat('EEE')`: na versão atual do `intl`
/// o pt_PT devolve o nome por extenso ("DOMINGO"), que num cartão de 54
/// pontos se parte em duas linhas ("DOMING/O"). Três letras são sempre
/// três letras, em qualquer versão e em qualquer língua do telemóvel.
const _abreviaturas = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];

class _DiaChip extends StatelessWidget {
  const _DiaChip({
    required this.dia,
    required this.eHoje,
    required this.escolhido,
    required this.aulas,
    required this.largura,
    required this.onTap,
  });

  final DateTime dia;
  final bool eHoje;
  final bool escolhido;
  final int aulas;
  final double largura;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final temAulas = aulas > 0;
    final semana = eHoje ? 'HOJE' : _abreviaturas[dia.weekday - 1];

    final corTexto = escolhido
        ? Colors.white
        : temAulas
            ? AppColors.bone
            : AppColors.dim;

    return Semantics(
      button: true,
      selected: escolhido,
      // O que um leitor de ecrã deve dizer: o dia por extenso e se há
      // aulas — o desenho (um ponto) não chega a quem não o vê.
      label: '${DateFormat('EEEE, d \'de\' MMMM', 'pt_PT').format(dia)}, '
          '${temAulas ? (aulas == 1 ? '1 aula' : '$aulas aulas') : 'sem aulas'}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: largura,
          // Margem vertical para a sombra do escolhido não ser cortada
          // pela altura da faixa.
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: escolhido ? AppColors.red : AppColors.subtleFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: escolhido ? AppColors.red : AppColors.cardBorder,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                semana,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: escolhido ? Colors.white70 : AppColors.mute,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${dia.day}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: corTexto,
                ),
              ),
              const SizedBox(height: 4),
              // O ponto diz "há aulas aqui" sem obrigar a tocar. Branco
              // no escolhido, que já está a vermelho.
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !temAulas
                      ? Colors.transparent
                      : escolhido
                          ? Colors.white
                          : AppColors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O último cartão da faixa, para alargar o horizonte quando o estúdio
/// não o limita.
class DayStripMore extends StatelessWidget {
  const DayStripMore({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    return Semantics(
      button: true,
      label: 'Ver mais dias',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 64 * escala,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: AppColors.mute),
              SizedBox(height: 2),
              Text(
                'Mais dias',
                style: TextStyle(fontSize: 10, color: AppColors.mute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
