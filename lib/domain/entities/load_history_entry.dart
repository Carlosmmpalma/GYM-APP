import 'package:equatable/equatable.dart';

/// Fase 8 (UC16 fechado, Firestore Data Model v1 §44) — um registo
/// histórico de carga de um exercício. "Cada alteração cria um novo
/// registo. Não sobrescrever o histórico" — nunca há update, só
/// create; o valor atual (mostrado no plano) é sempre o registo mais
/// recente por `exerciseId`, nunca um campo à parte que se sobrescreve.
///
/// Caminho simplificado de propósito: o guia/doc técnico escreve
/// `members/{id}/training/loadHistory/{recordId}`, mas isso não
/// resolve como um caminho Firestore válido (segmentos ímpares sem
/// um doc fixo intermédio claro) — modelado como subcoleção direta
/// `members/{id}/loadHistory/{recordId}`, mesmo padrão "flat" já
/// usado em todo o resto da app (`sessionOccurrences/{id}/bookings`,
/// `freeTrainingSchedules/{weekId}/slots`).
class LoadHistoryEntry extends Equatable {
  const LoadHistoryEntry({
    required this.id,
    required this.memberId,
    required this.exerciseId,
    required this.load,
    required this.reps,
    required this.recordedAt,
    required this.recordedBy,
  });

  final String id;
  final String memberId;
  final String exerciseId;

  /// kg — Domain Model v1 §34 chama-lhe "carga".
  final double load;
  final int reps;
  final DateTime recordedAt;

  /// uid de quem registou (Instrutor/Gestor) — nunca o próprio membro.
  final String recordedBy;

  @override
  List<Object?> get props =>
      [id, memberId, exerciseId, load, reps, recordedAt, recordedBy];
}
