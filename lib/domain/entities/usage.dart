import 'package:equatable/equatable.dart';

/// Read model derivado de `usage/{memberId}_{serviceId}_{period}`
/// (Firestore Data Model v1 §31/32 — "não é a fonte de verdade
/// histórica", reconstruível a partir dos `Booking`s reais pela Cloud
/// Function `recalculateUsage`, Fase 4 story 6).
///
/// Deliberadamente NÃO guarda `limit` aqui — o limite vive na
/// [UsageRule] do Plan atual (`PlanService.usage`), que pode mudar
/// (o Gestor edita a regra); duplicá-lo neste documento arriscava
/// ficar desatualizado. Quem precisa de mostrar "1/2" junta [used] (daqui)
/// com o `limit` vivo, lido à parte.
class Usage extends Equatable {
  const Usage({
    required this.memberId,
    required this.serviceId,
    required this.period,
    required this.used,
  });

  final String memberId;
  final String serviceId;

  /// Chave ISO-8601 week (`YYYY-Www`) — ver `core/utils/iso_week.dart`.
  final String period;
  final int used;

  @override
  List<Object?> get props => [memberId, serviceId, period, used];
}
