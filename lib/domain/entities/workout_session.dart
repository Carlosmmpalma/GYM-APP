import 'package:equatable/equatable.dart';

/// Uma série efetivamente FEITA, dentro de uma sessão de treino.
///
/// Distinta da prescrição ([TrainingPlanEntry], que diz "4 × 8-12"):
/// aqui é o que aconteceu — 8 repetições com 60 kg, às 18:42.
class SetLog extends Equatable {
  const SetLog({
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    required this.completedAt,
    this.load,
    this.loadHistoryId,
  });

  final String exerciseId;

  /// 1 para a primeira série do exercício, 2 para a segunda. Guardado em
  /// vez de derivado da posição na lista: apagar uma série a meio não
  /// deve renumerar as outras.
  final int setNumber;

  final int reps;

  /// `null` para exercícios sem carga (prancha, corrida, peso do corpo).
  final double? load;

  final DateTime completedAt;

  /// O registo de carga que esta série criou
  /// (`members/{id}/loadHistory/{recordId}`), quando houve carga.
  ///
  /// Guardado para que corrigir ou apagar a série corrija também o
  /// histórico. Sem esta ligação, um 6 escrito em vez de 60 ficava para
  /// sempre na evolução da carga: não havia forma de saber qual dos
  /// registos do exercício correspondia à série errada. `null` em
  /// séries sem carga e nas registadas antes desta ligação existir.
  final String? loadHistoryId;

  SetLog copyWith({int? reps, double? load, bool clearLoad = false}) {
    return SetLog(
      exerciseId: exerciseId,
      setNumber: setNumber,
      reps: reps ?? this.reps,
      load: clearLoad ? null : (load ?? this.load),
      completedAt: completedAt,
      loadHistoryId: loadHistoryId,
    );
  }

  @override
  List<Object?> get props =>
      [exerciseId, setNumber, reps, load, completedAt, loadHistoryId];
}

/// Fase 11 — uma sessão de treino: o que foi feito num dia.
///
/// A peça que faltava para isto ser um ginásio com acompanhamento a
/// sério. Havia a prescrição (o plano) e havia um histórico de cargas
/// solto por exercício — mas não havia o **treino**: a ida ao ginásio,
/// com as séries que se fizeram, na ordem em que se fizeram.
///
/// É o modelo a que as apps da área chegaram todas (Hevy, Strong,
/// Trainerize, TrueCoach): escolhe-se um treino do plano, abre-se uma
/// sessão, cada série confirma-se à medida que é feita, e no fim
/// fecha-se. O histórico é por sessão E por exercício.
///
/// **Quem regista** é a diferença entre uma app de auto-registo e uma de
/// acompanhamento. Aqui são os três: o aluno regista o seu treino, e o
/// instrutor ou o gestor registam por ele quando estão a acompanhá-lo ao
/// lado — que é como um estúdio com PT funciona.
///
/// Vive em `tenants/{t}/members/{memberId}/workoutSessions/{sessionId}`.
class WorkoutSession extends Equatable {
  const WorkoutSession({
    required this.id,
    required this.memberId,
    required this.workoutName,
    required this.startedAt,
    required this.performedBy,
    this.workoutId,
    this.finishedAt,
    this.notes = '',
    this.sets = const [],
  });

  final String id;
  final String memberId;

  /// O treino do plano que originou esta sessão. `null` para um treino
  /// avulso, fora do plano.
  final String? workoutId;

  /// Cópia do nome no momento em que a sessão começou.
  ///
  /// Denormalizado de propósito: um treino pode ser renomeado ou
  /// apagado, e o histórico tem de continuar a dizer o que a pessoa fez
  /// naquele dia. Um registo que muda de nome retroativamente não é um
  /// registo.
  final String workoutName;

  final DateTime startedAt;

  /// `null` enquanto a sessão está a decorrer. É isto que distingue "o
  /// treino de hoje, em curso" de uma sessão do histórico.
  final DateTime? finishedAt;

  /// Quem registou — o próprio aluno, ou o instrutor que o acompanhou.
  /// Fica no registo porque é informação de acompanhamento: "este treino
  /// foi feito com o instrutor" vale para quem o lê depois.
  final String performedBy;

  final String notes;

  final List<SetLog> sets;

  bool get isActive => finishedAt == null;

  Duration? get duration => finishedAt?.difference(startedAt);

  /// Volume total (kg × repetições). É a métrica que as apps da área
  /// usam para resumir uma sessão numa linha — séries sem carga não
  /// contam, porque multiplicar por zero apagaria a sessão toda.
  double get totalVolume => sets.fold(
        0,
        (total, set) => total + (set.load ?? 0) * set.reps,
      );

  int get totalReps => sets.fold(0, (total, set) => total + set.reps);

  /// Séries feitas de um exercício, por ordem.
  List<SetLog> setsFor(String exerciseId) =>
      sets.where((s) => s.exerciseId == exerciseId).toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

  @override
  List<Object?> get props => [
        id,
        memberId,
        workoutId,
        workoutName,
        startedAt,
        finishedAt,
        performedBy,
        notes,
        sets,
      ];
}
