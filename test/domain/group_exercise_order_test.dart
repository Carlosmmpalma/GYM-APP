import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/member_stats.dart';
import 'package:gym_saas/domain/entities/training_plan_entry.dart';

/// A ordem por que uma aula de grupo percorre os exercícios.
///
/// Neste estúdio cada aluno tem o SEU plano, por isso não existe uma
/// lista da aula. Esta função constrói uma a partir de quem está na
/// sala — é o que permite a vista "por exercício" existir sem inventar
/// um conceito novo de "plano da aula".
void main() {
  TrainingPlanEntry entrada(String memberId, String exerciseId, int position) {
    return TrainingPlanEntry(
      id: '${memberId}_$exerciseId',
      memberId: memberId,
      exerciseId: exerciseId,
      sets: 3,
      reps: '10',
      position: position,
    );
  }

  test('sem planos, não há ordem nenhuma', () {
    expect(groupExerciseOrder(const {}), isEmpty);
    expect(
      groupExerciseOrder({'ana': const <TrainingPlanEntry>[]}),
      isEmpty,
    );
  });

  test('com um plano só, segue a ordem desse plano', () {
    expect(
      groupExerciseOrder({
        'ana': [
          entrada('ana', 'agachamento', 0),
          entrada('ana', 'supino', 1),
          entrada('ana', 'remada', 2),
        ],
      }),
      ['agachamento', 'supino', 'remada'],
    );
  });

  test('turma com o mesmo circuito mantém a ordem do circuito', () {
    // O caso comum: o instrutor deu o mesmo plano a toda a gente.
    final plano = ['agachamento', 'supino', 'remada'];
    expect(
      groupExerciseOrder({
        for (final nome in ['ana', 'bruno', 'carla'])
          nome: [
            for (var i = 0; i < plano.length; i++) entrada(nome, plano[i], i),
          ],
      }),
      plano,
    );
  });

  test('junta planos diferentes sem repetir exercícios', () {
    final ordem = groupExerciseOrder({
      'ana': [entrada('ana', 'agachamento', 0), entrada('ana', 'supino', 1)],
      'bruno': [
        entrada('bruno', 'agachamento', 0),
        entrada('bruno', 'remada', 1)
      ],
    });

    expect(ordem, hasLength(3));
    expect(ordem.toSet(), {'agachamento', 'supino', 'remada'});
    expect(ordem.first, 'agachamento', reason: 'é o primeiro dos dois planos');
  });

  test('ordena pela posição MAIS BAIXA, não pela média', () {
    // O agachamento é o primeiro exercício de três alunos e o quinto de
    // um. Continua a ser por onde a aula começa — uma média punha-o
    // depois do supino, e a turma começaria pelo sítio errado.
    final ordem = groupExerciseOrder({
      'ana': [entrada('ana', 'agachamento', 0), entrada('ana', 'supino', 1)],
      'bruno': [
        entrada('bruno', 'agachamento', 0),
        entrada('bruno', 'supino', 1)
      ],
      'carla': [
        entrada('carla', 'agachamento', 0),
        entrada('carla', 'supino', 1)
      ],
      'diogo': [
        entrada('diogo', 'supino', 0),
        entrada('diogo', 'agachamento', 4)
      ],
    });

    expect(ordem.first, 'agachamento');
  });

  test('em empate, o que mais gente faz vem primeiro', () {
    // É onde a turma se junta — e é por aí que o instrutor quer
    // começar.
    final ordem = groupExerciseOrder({
      'ana': [entrada('ana', 'comum', 0)],
      'bruno': [entrada('bruno', 'comum', 0)],
      'carla': [entrada('carla', 'raro', 0)],
    });

    expect(ordem, ['comum', 'raro']);
  });

  test('a ordem é estável entre chamadas', () {
    // Sem um último critério de desempate, a lista trocava de ordem a
    // cada reconstrução do ecrã e o swipe saltava sozinho.
    Map<String, List<TrainingPlanEntry>> planos() => {
          'ana': [entrada('ana', 'zzz', 0)],
          'bruno': [entrada('bruno', 'aaa', 0)],
        };

    expect(groupExerciseOrder(planos()), groupExerciseOrder(planos()));
  });
}
