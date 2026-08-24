import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/exercise.dart';
import 'package:gym_saas/domain/entities/member_stats.dart';
import 'package:gym_saas/domain/entities/workout_session.dart';

const _memberId = 'member_1';

const _exercises = {
  'ex_supino': Exercise(
    id: 'ex_supino',
    name: 'Supino plano',
    description: '',
    muscleGroup: 'Peito',
  ),
  'ex_agachamento': Exercise(
    id: 'ex_agachamento',
    name: 'Agachamento',
    description: '',
    muscleGroup: 'Pernas',
  ),
  'ex_prancha': Exercise(
    id: 'ex_prancha',
    name: 'Prancha',
    description: '',
    muscleGroup: 'Core',
  ),
};

WorkoutSession _session({
  required String id,
  required DateTime startedAt,
  required List<SetLog> sets,
  bool finished = true,
}) {
  return WorkoutSession(
    id: id,
    memberId: _memberId,
    workoutName: 'Treino A',
    startedAt: startedAt,
    finishedAt: finished ? startedAt.add(const Duration(hours: 1)) : null,
    performedBy: _memberId,
    sets: sets,
  );
}

SetLog _set(
    String exerciseId, int number, int reps, double? load, DateTime at) {
  return SetLog(
    exerciseId: exerciseId,
    setNumber: number,
    reps: reps,
    load: load,
    completedAt: at,
  );
}

void main() {
  final agora = DateTime(2026, 8, 20, 18); // quinta-feira

  MemberStats statsOf(List<WorkoutSession> sessions) => computeMemberStats(
        sessions: sessions,
        exercisesById: _exercises,
        now: agora,
      );

  group('1RM estimado (Epley)', () {
    test('uma repetição é a própria carga', () {
      expect(estimateOneRepMax(load: 100, reps: 1), closeTo(103.3, 0.1));
    });

    test('cresce com as repetições', () {
      final cinco = estimateOneRepMax(load: 100, reps: 5)!;
      final dez = estimateOneRepMax(load: 100, reps: 10)!;
      expect(dez, greaterThan(cinco));
    });

    test('acima de 12 repetições não estima', () {
      // A fórmula afasta-se depressa da realidade: uma série de 20
      // daria um número que a pessoa nunca levantaria. Melhor não
      // dizer nada do que dizer uma coisa bonita e falsa.
      expect(estimateOneRepMax(load: 100, reps: 20), isNull);
    });

    test('sem carga não há 1RM', () {
      // Prancha, corrida, peso do corpo.
      expect(estimateOneRepMax(load: null, reps: 10), isNull);
      expect(estimateOneRepMax(load: 0, reps: 10), isNull);
    });
  });

  group('Consistência', () {
    test('sem treinos, não inventa nada', () {
      final stats = statsOf(const []);
      expect(stats.hasData, isFalse);
      expect(stats.lastSessionAt, isNull);
      expect(stats.weekStreak, 0);
      // As semanas vazias existem à mesma: são elas que dão a forma do
      // gráfico.
      expect(stats.weeks.length, 12);
      expect(stats.weeks.every((w) => w.sessions == 0), isTrue);
    });

    test('um treino a decorrer ainda não conta como treino feito', () {
      final stats = statsOf([
        _session(
          id: 's1',
          startedAt: agora.subtract(const Duration(hours: 1)),
          sets: [_set('ex_supino', 1, 8, 60, agora)],
          finished: false,
        ),
      ]);
      expect(stats.totalSessions, 0);
      expect(stats.sessionsInWindow, 0);
    });

    test('conta semanas seguidas com treino', () {
      final stats = statsOf([
        for (var semana = 0; semana < 3; semana++)
          _session(
            id: 's$semana',
            startedAt: agora.subtract(Duration(days: 7 * semana)),
            sets: [_set('ex_supino', 1, 8, 60, agora)],
          ),
      ]);
      expect(stats.weekStreak, 3);
    });

    test('uma semana em branco parte a sequência', () {
      final stats = statsOf([
        _session(
          id: 'esta',
          startedAt: agora,
          sets: [_set('ex_supino', 1, 8, 60, agora)],
        ),
        // Salta a semana passada.
        _session(
          id: 'ha_duas',
          startedAt: agora.subtract(const Duration(days: 14)),
          sets: [_set('ex_supino', 1, 8, 60, agora)],
        ),
      ]);
      expect(stats.weekStreak, 1);
    });

    test('a semana atual ainda a meio não zera a sequência', () {
      // Treinou as duas semanas anteriores e esta ainda não — à
      // segunda-feira de manhã ninguém treinou ainda, e zerar a
      // sequência aí seria castigar quem não fez nada de errado.
      final stats = statsOf([
        for (var semana = 1; semana <= 2; semana++)
          _session(
            id: 's$semana',
            startedAt: agora.subtract(Duration(days: 7 * semana)),
            sets: [_set('ex_supino', 1, 8, 60, agora)],
          ),
      ]);
      expect(stats.weekStreak, 2);
    });
  });

  group('Volume e equilíbrio', () {
    test('volume é carga × repetições, só na janela', () {
      final stats = statsOf([
        _session(
          id: 'recente',
          startedAt: agora.subtract(const Duration(days: 3)),
          sets: [_set('ex_supino', 1, 10, 50, agora)], // 500
        ),
        _session(
          id: 'antigo',
          startedAt: agora.subtract(const Duration(days: 90)),
          sets: [_set('ex_supino', 1, 10, 100, agora)], // fora da janela
        ),
      ]);
      expect(stats.volumeInWindow, 500);
      expect(stats.sessionsInWindow, 1);
      // O histórico completo continua a contar para o resto.
      expect(stats.totalSessions, 2);
    });

    test('agrupa séries por grupo muscular', () {
      // É aqui que se vê quem faz peito três vezes por semana e pernas
      // nunca.
      final stats = statsOf([
        _session(
          id: 's1',
          startedAt: agora.subtract(const Duration(days: 2)),
          sets: [
            _set('ex_supino', 1, 10, 50, agora),
            _set('ex_supino', 2, 10, 50, agora),
            _set('ex_agachamento', 1, 10, 80, agora),
          ],
        ),
      ]);
      expect(stats.setsByMuscleGroup['Peito'], 2);
      expect(stats.setsByMuscleGroup['Pernas'], 1);
      expect(stats.setsByMuscleGroup.containsKey('Core'), isFalse);
    });

    test('um exercício desconhecido não desaparece da contagem', () {
      final stats = statsOf([
        _session(
          id: 's1',
          startedAt: agora.subtract(const Duration(days: 2)),
          sets: [_set('ex_apagado', 1, 10, 50, agora)],
        ),
      ]);
      expect(stats.setsByMuscleGroup['Sem grupo'], 1);
    });
  });

  group('Força por exercício', () {
    test('a melhor série é a de maior 1RM, não a de mais repetições', () {
      final stats = statsOf([
        _session(
          id: 's1',
          startedAt: agora.subtract(const Duration(days: 2)),
          sets: [
            _set('ex_supino', 1, 12, 60, agora), // e1RM 84
            _set('ex_supino', 2, 5, 80, agora), // e1RM ~93 ← melhor
          ],
        ),
      ]);
      final supino = stats.strengthByExercise.single;
      expect(supino.bestLoad, 80);
      expect(supino.bestLoadReps, 5);
      expect(supino.estimatedOneRm, closeTo(93.3, 0.1));
    });

    test('mede a progressão desde o primeiro registo', () {
      final stats = statsOf([
        _session(
          id: 'antigo',
          startedAt: agora.subtract(const Duration(days: 60)),
          sets: [_set('ex_supino', 1, 10, 60, agora)], // e1RM 80
        ),
        _session(
          id: 'recente',
          startedAt: agora.subtract(const Duration(days: 2)),
          sets: [_set('ex_supino', 1, 10, 72, agora)], // e1RM 96
        ),
      ]);
      final supino = stats.strengthByExercise.single;
      expect(supino.firstEstimatedOneRm, closeTo(80, 0.1));
      expect(supino.estimatedOneRm, closeTo(96, 0.1));
      expect(supino.progressPercent, closeTo(20, 0.1));
    });

    test('um exercício sem carga aparece, mas sem 1RM', () {
      final stats = statsOf([
        _session(
          id: 's1',
          startedAt: agora.subtract(const Duration(days: 2)),
          sets: [_set('ex_prancha', 1, 45, null, agora)],
        ),
      ]);
      final prancha = stats.strengthByExercise.single;
      expect(prancha.name, 'Prancha');
      expect(prancha.totalSets, 1);
      expect(prancha.estimatedOneRm, isNull);
      expect(prancha.progressPercent, isNull);
    });

    test('ordena pelos exercícios mais treinados', () {
      final stats = statsOf([
        _session(
          id: 's1',
          startedAt: agora.subtract(const Duration(days: 5)),
          sets: [
            _set('ex_supino', 1, 8, 60, agora),
            _set('ex_agachamento', 1, 8, 90, agora),
          ],
        ),
        _session(
          id: 's2',
          startedAt: agora.subtract(const Duration(days: 2)),
          sets: [_set('ex_agachamento', 1, 8, 95, agora)],
        ),
      ]);
      expect(stats.strengthByExercise.first.exerciseId, 'ex_agachamento');
      expect(stats.strengthByExercise.first.sessions, 2);
    });
  });
}
