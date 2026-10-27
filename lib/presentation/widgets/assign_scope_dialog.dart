import 'package:flutter/material.dart';

/// A que aulas se aplica uma atribuição numa série recorrente.
enum AssignScope {
  /// Só a aula daquele dia.
  estaAula,

  /// Esta e todas as semanas seguintes — incluindo as que ainda não
  /// foram geradas.
  todasAsSemanas,
}

/// Perguntar "só esta aula ou todas as semanas?" antes de atribuir.
///
/// Até aqui o "Adicionar membro" atingia sempre **uma data**. Numa aula
/// que se repete toda a semana, inscrever um aluno obrigava a repetir
/// o gesto semana a semana — e nas semanas ainda não geradas não havia
/// sequer onde o fazer.
///
/// A pergunta só aparece quando a aula pertence a uma série. Numa aula
/// avulsa não há decisão nenhuma a tomar, e um diálogo com uma única
/// resposta possível é só um toque a mais.
///
/// Devolve `null` se a pessoa fechar sem escolher.
Future<AssignScope?> showAssignScopeDialog({
  required BuildContext context,
  required int quantosMembros,
}) {
  final pessoas =
      quantosMembros == 1 ? 'este aluno' : 'estes $quantosMembros alunos';

  return showDialog<AssignScope>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Marcar em que aulas?'),
      content: Text(
        'Esta aula repete-se todas as semanas. Queres marcar $pessoas só '
        'nesta data, ou em todas as semanas?',
      ),
      // Em coluna e não lado a lado: são duas frases, não dois verbos,
      // e lado a lado ficariam cortadas num telemóvel estreito.
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(AssignScope.estaAula),
          child: const Text('Só esta aula'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(AssignScope.todasAsSemanas),
          child: const Text('Todas as semanas'),
        ),
      ],
    ),
  );
}

/// A frase a mostrar depois de atribuir à série inteira.
///
/// Uma semana que falhe — sala cheia, limite semanal esgotado — não
/// impede as outras, por isso o resultado é quase sempre parcial e
/// dizer só "atribuído" seria mentira. Mas "6 marcadas, 2 falhadas"
/// também não ajuda: o que a pessoa precisa de saber é se tem de fazer
/// alguma coisa.
String resumoDaAtribuicaoNaSerie({
  required int totalAssigned,
  required int totalSkipped,
  required int occurrences,
}) {
  if (occurrences == 0) {
    return 'Marcado nas semanas futuras. Ainda não há aulas geradas — '
        'aparecem assim que forem criadas.';
  }
  if (totalSkipped == 0) {
    return 'Marcado em $totalAssigned aula(s), e nas semanas que vierem.';
  }
  if (totalAssigned == 0) {
    return 'Não foi possível marcar em nenhuma das $occurrences aulas '
        '(sem vaga, sem plano ativo ou limite semanal atingido). Fica na '
        'lista da série para as semanas que vierem.';
  }
  return 'Marcado em $totalAssigned aula(s). Em $totalSkipped não deu '
      '(sem vaga ou limite semanal). Fica na lista para as semanas que vierem.';
}
