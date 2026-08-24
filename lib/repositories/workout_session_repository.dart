import '../domain/entities/workout_session.dart';

/// Fase 11 — registar o que foi FEITO num treino.
///
/// O plano diz o que fazer; isto diz o que aconteceu. Os três papéis
/// registam: o aluno o seu próprio treino, e o instrutor ou o gestor por
/// ele quando o acompanham — que é como um estúdio com PT funciona.
abstract class WorkoutSessionRepository {
  /// Histórico, da sessão mais recente para a mais antiga.
  Stream<List<WorkoutSession>> watchSessions(String memberId);

  /// A sessão em curso, se houver. `null` quando não há treino a
  /// decorrer.
  ///
  /// Só pode haver uma de cada vez: duas sessões abertas ao mesmo tempo
  /// significaria não saber a qual pertence a próxima série registada.
  Stream<WorkoutSession?> watchActiveSession(String memberId);

  /// Abre uma sessão. [workoutName] é copiado para o registo — o treino
  /// pode ser renomeado ou apagado, e o histórico tem de continuar a
  /// dizer o que a pessoa fez.
  Future<String> startSession({
    required String memberId,
    required String? workoutId,
    required String workoutName,
    required String performedBy,
  });

  /// Confirma uma série feita.
  ///
  /// Escreve também no histórico de cargas do exercício quando há carga:
  /// é o que alimenta o gráfico de evolução, que já existia antes das
  /// sessões e continua a ser a forma de responder a "quanto é que eu
  /// levantava há três meses".
  Future<void> logSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required int reps,
    double? load,
    required String performedBy,
  });

  /// Remove a última série registada de um exercício. O erro mais comum
  /// a registar ao vivo é confirmar uma série a mais, e não deve exigir
  /// abrir um ecrã de edição.
  Future<void> undoLastSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
  });

  /// Corrige uma série já confirmada — 6 kg escritos em vez de 60, ou
  /// 8 repetições registadas quando saíram 6.
  ///
  /// "Anular a última" só chega quando o erro foi na última: a correção
  /// de uma série a meio obrigava a apagar tudo o que veio depois e a
  /// registá-lo outra vez de cabeça.
  ///
  /// Corrige também o registo de carga que a série original criou (ver
  /// [SetLog.loadHistoryId]) — o histórico é append-only por princípio,
  /// mas um valor errado não é histórico, é um engano por corrigir.
  Future<void> updateSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required int reps,
    double? load,
    required String performedBy,
  });

  /// Apaga uma série concreta (não necessariamente a última), e com ela
  /// o registo de carga que criou.
  Future<void> deleteSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
    required int setNumber,
  });

  Future<void> finishSession({
    required String memberId,
    required String sessionId,
    String notes = '',
  });

  /// Apaga uma sessão em curso sem a guardar no histórico — para quem
  /// abre por engano. Uma sessão já terminada não se descarta: isso é
  /// histórico.
  Future<void> discardSession({
    required String memberId,
    required String sessionId,
  });
}
