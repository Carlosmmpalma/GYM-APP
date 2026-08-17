import 'package:equatable/equatable.dart';

enum FreeTrainingScheduleStatus { draft, suggested, published }

/// Fase 7 (Firestore Data Model v1 §39, UC17-A) — grelha semanal do
/// "Treino sem acompanhamento": `weekId` é o documento
/// (`tenants/{t}/freeTrainingSchedules/{weekId}`), formato
/// `YYYY-MM-DD` da segunda-feira dessa semana (mesma convenção ISO já
/// usada por `iso_week.dart`).
///
/// Estado (UC17-A fechado): "o sistema deve SUGERIR a grelha... mas
/// nunca aplicá-la sozinho — o Gestor tem sempre de rever e aprovar
/// antes de ficar visível para os alunos." `draft` = semana sem
/// nenhuma sugestão nem semana anterior para copiar (Gestor começa do
/// zero); `suggested` = copiada automaticamente de uma semana
/// anterior, ainda por rever; `published` = visível ao Aluno.
class FreeTrainingSchedule extends Equatable {
  const FreeTrainingSchedule({
    required this.weekId,
    required this.weekStart,
    required this.status,
    this.createdBy,
    this.publishedAt,
  });

  final String weekId;
  final DateTime weekStart;
  final FreeTrainingScheduleStatus status;
  final String? createdBy;
  final DateTime? publishedAt;

  bool get isPublished => status == FreeTrainingScheduleStatus.published;

  @override
  List<Object?> get props =>
      [weekId, weekStart, status, createdBy, publishedAt];
}
