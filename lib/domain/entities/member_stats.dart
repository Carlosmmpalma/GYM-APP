import 'package:equatable/equatable.dart';

import '../../core/utils/iso_week.dart';
import 'exercise.dart';
import 'training_plan_entry.dart';
import 'workout_session.dart';

/// Estatísticas de treino de UM aluno, calculadas a partir do que ele
/// fez — não do que lhe foi prescrito.
///
/// As métricas são as que as apps da área convergiram em mostrar
/// (Hevy, Strong, Trainerize, TrueCoach), pela mesma ordem de
/// importância que elas lhes dão:
///
///  1. **Consistência** — quantos treinos por semana. É o número que
///     melhor prevê se alguém continua sócio daqui a seis meses, e o
///     único que se traduz numa conversa imediata ("faltaste duas
///     semanas, está tudo bem?").
///  2. **Volume** (carga × repetições) — o total de trabalho. Sozinho
///     diz pouco; a variação ao longo das semanas diz muito.
///  3. **Equilíbrio** — séries por grupo muscular. É onde se vê que
///     alguém faz peito três vezes por semana e pernas nunca.
///  4. **Força por exercício** — a melhor série e a estimativa de 1RM,
///     que é como toda a gente na área fala de progressão.
///
/// Tudo isto sai das sessões de treino já carregadas (uma query) e da
/// biblioteca de exercícios (já em memória): o ecrã não custa uma
/// leitura a mais do que a ficha do aluno já custava.
class MemberStats extends Equatable {
  const MemberStats({
    required this.windowDays,
    required this.sessionsInWindow,
    required this.volumeInWindow,
    required this.setsInWindow,
    required this.lastSessionAt,
    required this.weekStreak,
    required this.weeks,
    required this.setsByMuscleGroup,
    required this.strengthByExercise,
    required this.totalSessions,
  });

  /// Janela das métricas "recentes" (30 dias por omissão).
  final int windowDays;

  final int sessionsInWindow;
  final double volumeInWindow;
  final int setsInWindow;

  /// Quando foi o último treino REGISTADO. `null` = nunca registou
  /// nenhum — que é diferente de "não treina": pode treinar e ninguém
  /// registar, e o ecrã diz isso em vez de acusar o aluno.
  final DateTime? lastSessionAt;

  /// Semanas seguidas com pelo menos um treino.
  final int weekStreak;

  /// Uma entrada por semana, da mais antiga para a mais recente.
  final List<TrainingWeek> weeks;

  /// Séries por grupo muscular na janela — a leitura de equilíbrio.
  final Map<String, int> setsByMuscleGroup;

  /// Ordenada pelos exercícios mais treinados.
  final List<ExerciseStrength> strengthByExercise;

  /// Todos os treinos conhecidos (o histórico carregado), não só os da
  /// janela.
  final int totalSessions;

  bool get hasData => totalSessions > 0;

  int? get daysSinceLastSession => lastSessionAt == null
      ? null
      : DateTime.now().difference(lastSessionAt!).inDays;

  @override
  List<Object?> get props => [
        windowDays,
        sessionsInWindow,
        volumeInWindow,
        setsInWindow,
        lastSessionAt,
        weekStreak,
        weeks,
        setsByMuscleGroup,
        strengthByExercise,
        totalSessions,
      ];
}

/// Uma semana no gráfico de consistência.
class TrainingWeek extends Equatable {
  const TrainingWeek({
    required this.monday,
    required this.sessions,
    required this.volume,
  });

  final DateTime monday;
  final int sessions;
  final double volume;

  @override
  List<Object?> get props => [monday, sessions, volume];
}

/// A força num exercício concreto.
class ExerciseStrength extends Equatable {
  const ExerciseStrength({
    required this.exerciseId,
    required this.name,
    required this.sessions,
    required this.totalSets,
    required this.bestLoad,
    required this.bestLoadReps,
    required this.estimatedOneRm,
    required this.firstEstimatedOneRm,
    required this.lastPerformedAt,
  });

  final String exerciseId;
  final String name;

  /// Em quantos treinos este exercício apareceu.
  final int sessions;
  final int totalSets;

  /// A melhor série: a de maior 1RM estimado, ou a de maior carga
  /// quando não há nenhuma estimável.
  final double bestLoad;
  final int bestLoadReps;

  /// `null` para exercícios sem carga ou só com séries longas — ver
  /// [estimateOneRepMax].
  final double? estimatedOneRm;

  /// A mesma estimativa no treino mais antigo do histórico, para
  /// medir o caminho andado.
  final double? firstEstimatedOneRm;

  final DateTime lastPerformedAt;

  /// Variação percentual da estimativa desde o primeiro registo.
  /// `null` quando não há termo de comparação.
  double? get progressPercent {
    final first = firstEstimatedOneRm;
    final current = estimatedOneRm;
    if (first == null || current == null || first <= 0) return null;
    return (current - first) / first * 100;
  }

  @override
  List<Object?> get props => [
        exerciseId,
        name,
        sessions,
        totalSets,
        bestLoad,
        bestLoadReps,
        estimatedOneRm,
        firstEstimatedOneRm,
        lastPerformedAt,
      ];
}

/// Estimativa de 1RM pela fórmula de Epley: `carga × (1 + reps/30)`.
///
/// É a que praticamente toda a gente na área usa, e é boa até cerca de
/// 12 repetições. Acima disso afasta-se depressa da realidade (uma
/// série de 20 repetições daria um número que a pessoa nunca levantaria)
/// — por isso devolve `null` em vez de um número bonito e falso.
///
/// Também `null` sem carga: uma prancha ou uma corrida não têm 1RM, e
/// inventar um seria pior do que não mostrar nada.
double? estimateOneRepMax({double? load, required int reps}) {
  if (load == null || load <= 0) return null;
  if (reps <= 0 || reps > 12) return null;
  return load * (1 + reps / 30);
}

/// Calcula tudo a partir do histórico já carregado.
///
/// Função pura de propósito: as decisões que aqui estão (o que conta
/// como treino, como se mede progressão, o que é uma sequência) são
/// regras de negócio, e é assim que se conseguem testar sem Firestore
/// nenhum à volta.
MemberStats computeMemberStats({
  required List<WorkoutSession> sessions,
  required Map<String, Exercise> exercisesById,
  required DateTime now,
  int windowDays = 30,
  int weekCount = 12,
}) {
  // Só treinos TERMINADOS. Um treino a decorrer ainda não é um treino
  // feito — contá-lo faria a contagem oscilar durante a própria sessão.
  final finished = sessions.where((s) => !s.isActive).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final windowStart = now.subtract(Duration(days: windowDays));
  final inWindow =
      finished.where((s) => s.startedAt.isAfter(windowStart)).toList();

  final setsByMuscleGroup = <String, int>{};
  for (final session in inWindow) {
    for (final set in session.sets) {
      final group = exercisesById[set.exerciseId]?.category;
      final key = (group == null || group.isEmpty) ? 'Sem grupo' : group;
      setsByMuscleGroup[key] = (setsByMuscleGroup[key] ?? 0) + 1;
    }
  }

  return MemberStats(
    windowDays: windowDays,
    sessionsInWindow: inWindow.length,
    volumeInWindow: inWindow.fold<double>(0, (sum, s) => sum + s.totalVolume),
    setsInWindow: inWindow.fold<int>(0, (sum, s) => sum + s.sets.length),
    lastSessionAt: finished.isEmpty ? null : finished.first.startedAt,
    weekStreak: _weekStreak(finished, now),
    weeks: _weeks(finished, now, weekCount),
    setsByMuscleGroup: setsByMuscleGroup,
    strengthByExercise: _strength(finished, exercisesById),
    totalSessions: finished.length,
  );
}

/// Semanas seguidas com pelo menos um treino.
///
/// Uma semana sem treinos parte a sequência — exceto a SEMANA ATUAL,
/// que ainda vai a meio: quem treinou todas as semanas até domingo
/// passado tem uma sequência de verdade, e zerá-la à segunda-feira de
/// manhã seria castigar alguém por ainda não ter ido ao ginásio hoje.
int _weekStreak(List<WorkoutSession> finished, DateTime now) {
  if (finished.isEmpty) return 0;

  final weeksWithTraining =
      finished.map((s) => isoWeekKey(s.startedAt)).toSet();

  var cursor = isoWeekRange(now).start;
  var streak = 0;
  // Se ainda não treinou esta semana, a contagem começa na anterior.
  if (!weeksWithTraining.contains(isoWeekKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 7));
  }
  while (weeksWithTraining.contains(isoWeekKey(cursor))) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return streak;
}

/// As últimas [weekCount] semanas, incluindo as vazias — são elas que
/// dão a forma do gráfico. Sem elas, três treinos em três meses
/// desenhavam a mesma linha que três treinos numa semana.
List<TrainingWeek> _weeks(
  List<WorkoutSession> finished,
  DateTime now,
  int weekCount,
) {
  final thisMonday = isoWeekRange(now).start;
  final buckets = <DateTime, TrainingWeek>{};
  for (var i = weekCount - 1; i >= 0; i--) {
    final monday = thisMonday.subtract(Duration(days: 7 * i));
    buckets[monday] = TrainingWeek(monday: monday, sessions: 0, volume: 0);
  }

  for (final session in finished) {
    final monday = isoWeekRange(session.startedAt).start;
    final bucket = buckets[monday];
    if (bucket == null) continue; // fora da janela do gráfico
    buckets[monday] = TrainingWeek(
      monday: monday,
      sessions: bucket.sessions + 1,
      volume: bucket.volume + session.totalVolume,
    );
  }

  return buckets.values.toList()..sort((a, b) => a.monday.compareTo(b.monday));
}

List<ExerciseStrength> _strength(
  List<WorkoutSession> finished,
  Map<String, Exercise> exercisesById,
) {
  // O histórico chega do mais recente para o mais antigo; para saber
  // "onde começou" é preciso percorrê-lo ao contrário.
  final oldestFirst = finished.reversed.toList();

  final sessionsPerExercise = <String, int>{};
  final setsPerExercise = <String, int>{};
  final bestLoad = <String, double>{};
  final bestLoadReps = <String, int>{};
  final bestOneRm = <String, double>{};
  final firstOneRm = <String, double>{};
  final lastPerformed = <String, DateTime>{};

  for (final session in oldestFirst) {
    final exercisesInSession = <String>{};
    for (final set in session.sets) {
      final id = set.exerciseId;
      exercisesInSession.add(id);
      setsPerExercise[id] = (setsPerExercise[id] ?? 0) + 1;
      lastPerformed[id] = session.startedAt;

      final load = set.load ?? 0;
      if (load > (bestLoad[id] ?? -1)) {
        bestLoad[id] = load;
        bestLoadReps[id] = set.reps;
      }

      final oneRm = estimateOneRepMax(load: set.load, reps: set.reps);
      if (oneRm != null) {
        // A primeira estimativa que aparece no histórico é a
        // referência; as seguintes só contam se forem melhores.
        firstOneRm.putIfAbsent(id, () => oneRm);
        if (oneRm > (bestOneRm[id] ?? -1)) bestOneRm[id] = oneRm;
      }
    }
    for (final id in exercisesInSession) {
      sessionsPerExercise[id] = (sessionsPerExercise[id] ?? 0) + 1;
    }
  }

  final result = <ExerciseStrength>[];
  for (final id in setsPerExercise.keys) {
    result.add(
      ExerciseStrength(
        exerciseId: id,
        name: exercisesById[id]?.name ?? id,
        sessions: sessionsPerExercise[id] ?? 0,
        totalSets: setsPerExercise[id] ?? 0,
        bestLoad: bestLoad[id] ?? 0,
        bestLoadReps: bestLoadReps[id] ?? 0,
        estimatedOneRm: bestOneRm[id],
        firstEstimatedOneRm: firstOneRm[id],
        lastPerformedAt: lastPerformed[id]!,
      ),
    );
  }

  // Os mais treinados primeiro: é onde está a informação com peso.
  result.sort((a, b) {
    final byFrequency = b.sessions.compareTo(a.sessions);
    if (byFrequency != 0) return byFrequency;
    return b.totalSets.compareTo(a.totalSets);
  });
  return result;
}

/// A ordem por que uma turma percorre os exercícios.
///
/// Numa aula de grupo o instrutor chama o exercício e toda a gente o
/// faz — mas neste estúdio cada aluno tem o SEU plano, por isso não
/// existe uma lista da aula. Esta função constrói uma: junta os planos
/// de quem está na sala e ordena os exercícios por onde aparecem.
///
/// Ordena pela posição MAIS BAIXA em que o exercício aparece em algum
/// plano, e não pela média: se o agachamento é o primeiro exercício de
/// três alunos e o quinto de um, continua a ser por onde a aula começa.
/// Empates desfazem-se pelo número de alunos que o têm — o que mais
/// gente faz vem primeiro, porque é onde a turma se junta.
///
/// Evita inventar um conceito de "plano da aula" que não existe no
/// domínio: a lista sai do que os alunos já têm prescrito, e muda
/// sozinha quando os planos mudam.
List<String> groupExerciseOrder(
  Map<String, List<TrainingPlanEntry>> plansByMember,
) {
  final firstPosition = <String, int>{};
  final howMany = <String, int>{};

  for (final entries in plansByMember.values) {
    for (final entry in entries) {
      final current = firstPosition[entry.exerciseId];
      if (current == null || entry.position < current) {
        firstPosition[entry.exerciseId] = entry.position;
      }
      howMany[entry.exerciseId] = (howMany[entry.exerciseId] ?? 0) + 1;
    }
  }

  final ids = firstPosition.keys.toList();
  ids.sort((a, b) {
    final byPosition = firstPosition[a]!.compareTo(firstPosition[b]!);
    if (byPosition != 0) return byPosition;
    final byCount = howMany[b]!.compareTo(howMany[a]!);
    if (byCount != 0) return byCount;
    // Último critério só para a ordem ser estável entre reconstruções.
    return a.compareTo(b);
  });
  return ids;
}
