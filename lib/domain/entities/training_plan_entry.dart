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
    this.workoutId,
    this.position = 0,
    this.restSeconds,
    this.notes = '',
  });

  final String id;
  final String memberId;
  final String exerciseId;
  final int sets;

  /// A prescrição, em texto: "10", "8-12", "45s", "até à falha".
  ///
  /// Era um `int`, e isso não chegava para o que um instrutor
  /// realmente escreve. O próprio comentário desta classe dava o
  /// exemplo que o modelo não conseguia representar — "Prancha — 45s" —
  /// e a app tinha de o guardar como um número de repetições que não
  /// significava nada.
  ///
  /// O histórico de cargas continua com repetições em número
  /// ([LoadHistoryEntry.reps]): aí é o que foi MESMO feito, e isso é
  /// sempre contável.
  final String reps;

  final double? currentLoad;

  /// A que treino pertence ("Treino A — Costas"). `null` = exercício
  /// solto, de antes de existirem treinos; a UI agrupa-os em "Sem
  /// treino atribuído" para o instrutor os poder arrumar.
  final String? workoutId;

  /// Ordem dentro do treino. A sequência dos exercícios não é
  /// decorativa: agachamento antes de extensão de pernas é uma decisão
  /// de treino.
  final int position;

  /// Descanso entre séries. `null` = o instrutor não especificou.
  final int? restSeconds;

  /// Nota para este exercício em concreto: "cadência 3-1-1", "só até
  /// meio arco", "se doer o ombro, para".
  final String notes;

  @override
  List<Object?> get props => [
        id,
        memberId,
        exerciseId,
        sets,
        reps,
        currentLoad,
        workoutId,
        position,
        restSeconds,
        notes,
      ];
}
