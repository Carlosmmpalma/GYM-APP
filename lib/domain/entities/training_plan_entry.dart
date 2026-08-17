import 'package:equatable/equatable.dart';

/// Fase 8 (UC13/UC15/UC16, "Editor de plano" no mockup) — uma
/// prescrição de exercício dentro do plano de treino de UM membro
/// (`tenants/{tenantId}/members/{memberId}/planEntries/{entryId}`).
/// O exercício em si (nome/descrição/vídeo) vive sempre na biblioteca
/// partilhada ([Exercise]) — aqui só fica a referência ([exerciseId])
/// + a prescrição específica deste membro (séries/reps/carga).
///
/// [currentLoad] é sempre o valor mais recente — nunca a fonte de
/// verdade do histórico (essa é [LoadHistoryEntry]); atualizar isto
/// tem de, na mesma operação, acrescentar um novo `LoadHistoryEntry`
/// (UC16 fechado: "nunca sobrescrever"). `null` para exercícios sem
/// carga (ex.: Prancha — "45s", isométrico, mostrado como "—" no
/// mockup).
class TrainingPlanEntry extends Equatable {
  const TrainingPlanEntry({
    required this.id,
    required this.memberId,
    required this.exerciseId,
    required this.sets,
    required this.reps,
    this.currentLoad,
  });

  final String id;
  final String memberId;
  final String exerciseId;
  final int sets;
  final int reps;
  final double? currentLoad;

  @override
  List<Object?> get props =>
      [id, memberId, exerciseId, sets, reps, currentLoad];
}
