import 'package:equatable/equatable.dart';

/// Fase 11 — o que o painel de retenção mostra ao Gestor.
///
/// Calculado no servidor (`getRetentionOverview`), não aqui: agregar
/// isto obriga a ler as presenças de todas as sessões do mês, e essas
/// vivem em subcoleções que o cliente nem sequer pode percorrer de uma
/// vez (as Security Rules não abrem `attendance` a collection group
/// queries, de propósito).
class RetentionOverview extends Equatable {
  const RetentionOverview({
    required this.windowDays,
    required this.riskWeeks,
    required this.scanDays,
    required this.membersWithActivePlan,
    required this.sessions,
    required this.occupancyPercent,
    required this.attendanceRecorded,
    required this.noShows,
    required this.noShowPercent,
    required this.atRisk,
  });

  /// Janela usada nas taxas (ocupação, faltas).
  final int windowDays;

  /// Sem presença há mais do que isto = em risco.
  final int riskWeeks;

  /// Até onde se procurou presença. Um aluno sem nenhuma presença
  /// encontrada pode ter vindo antes disto — daí a app dizer "sem
  /// presença nos últimos N dias" e nunca "nunca veio".
  final int scanDays;

  final int membersWithActivePlan;

  /// Sessões já realizadas dentro da janela.
  final int sessions;

  /// `null` quando não houve sessões com lugares na janela — diferente
  /// de 0%, que seria "houve aulas e não veio ninguém".
  final int? occupancyPercent;

  final int attendanceRecorded;
  final int noShows;

  /// `null` quando ninguém registou presenças na janela. É o caso mais
  /// provável de todos no início, e mostrar "0% de faltas" aí seria
  /// dizer que está tudo bem quando na verdade não se sabe.
  final int? noShowPercent;

  final List<MemberAtRisk> atRisk;

  @override
  List<Object?> get props => [
        windowDays,
        riskWeeks,
        scanDays,
        membersWithActivePlan,
        sessions,
        occupancyPercent,
        attendanceRecorded,
        noShows,
        noShowPercent,
        atRisk,
      ];
}

/// Alguém com plano ativo que deixou de aparecer. Não inclui quem já
/// não tem plano: essa pessoa não está em risco de sair, já saiu.
class MemberAtRisk extends Equatable {
  const MemberAtRisk({
    required this.memberId,
    required this.name,
    required this.memberNumber,
    required this.lastAttendanceAt,
  });

  final String memberId;
  final String name;
  final String memberNumber;

  /// `null` = nenhuma presença registada dentro do período procurado.
  final DateTime? lastAttendanceAt;

  @override
  List<Object?> get props => [memberId, name, memberNumber, lastAttendanceAt];
}
