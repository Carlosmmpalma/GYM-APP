import 'package:flutter/material.dart';

import '../../core/utils/time_range.dart';
import '../../core/theme/app_colors.dart';

/// Início e fim de uma aula, com atalhos para as durações do costume.
///
/// Substitui um campo de texto que pedia a **duração em minutos**. Quem
/// marca uma aula pensa "das seis às sete", não "sessenta"; escrever o
/// número obrigava a fazer a conta de cabeça e depois a confiar nela,
/// sem nunca ver a que horas a aula acabava.
///
/// Três decisões:
///
///  * **Fim como hora, não como duração.** É o mesmo gesto que o treino
///    livre já usava, e é o que o Google Calendar faz. A duração passa
///    a ser mostrada, não escrita.
///  * **Atalhos para 45 min, 1 h e 1 h 30**, porque uma aula de ginásio
///    é quase sempre uma destas. Mesmo espírito dos chips de capacidade
///    ("Individual/Duo/Trio") que já existiam ao lado.
///  * **O erro aparece antes de gravar.** Um botão desativado sem dizer
///    porquê é o que faz alguém perguntar "porque não consigo?".
class TimeRangeField extends StatelessWidget {
  const TimeRangeField({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
    this.compact = false,
  });

  final TimeOfDay start;
  final TimeOfDay end;

  /// Recebe sempre o par completo — quem usa isto não tem de saber qual
  /// dos dois mexeu.
  final void Function(TimeOfDay start, TimeOfDay end) onChanged;

  /// Dentro de um diálogo, onde o espaço vertical é escasso.
  final bool compact;

  static const _presets = [45, 60, 90];

  @override
  Widget build(BuildContext context) {
    final valid = endsAfterStart(start, end);
    final minutes = durationInMinutes(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _TimeTile(
                label: 'Início',
                time: start,
                onPicked: (picked) {
                  // Mexer no início arrasta o fim, mantendo a duração:
                  // adiar uma aula uma hora não devia obrigar a corrigir
                  // as duas pontas.
                  final kept = valid ? minutes : 60;
                  onChanged(picked, addMinutes(picked, kept));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TimeTile(
                label: 'Fim',
                time: end,
                trailingText: valid ? formatDuration(minutes) : null,
                onPicked: (picked) => onChanged(start, picked),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        Wrap(
          spacing: 6,
          children: [
            for (final preset in _presets)
              ChoiceChip(
                label: Text(formatDuration(preset)),
                selected: valid && minutes == preset,
                onSelected: (_) => onChanged(start, addMinutes(start, preset)),
              ),
          ],
        ),
        if (!valid) ...[
          const SizedBox(height: 6),
          Text(
            'A hora de fim tem de ser depois da de início.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onPicked,
    this.trailingText,
  });

  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPicked;

  /// A duração, ao lado do fim. É a informação que o campo de minutos
  /// dava e que o relógio sozinho perdia.
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.schedule_outlined, size: 18),
        ),
        // Os dois campos vivem lado a lado dentro de um formulário: num
        // Android de 360 pontos sobram 92 px para cada um, depois do
        // `Expanded`, do espaçamento e da moldura do `InputDecorator`.
        // A hora tinha `Flexible` no acompanhante mas não em si própria,
        // por isso pedia a largura que quisesse e a linha estourava —
        // 8 px num iPhone SE com letra normal, 106 px a 2.0×.
        //
        // A ordem de quem cede importa: a duração é uma ajuda e pode
        // ser cortada; a HORA é o valor do campo e nunca. Por isso a
        // duração desaparece quando não há espaço para as duas, em vez
        // de as duas ficarem ilegíveis.
        child: Row(
          children: [
            Flexible(
              child: Text(
                time.format(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingText != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailingText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
