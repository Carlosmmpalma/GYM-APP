import 'package:equatable/equatable.dart';

import 'usage_rule.dart';

/// Domain Model v1 §12 / Firestore Data Model v1 §14 — a relação
/// Plan↔Service (N:N) é uma entidade conceptual própria, não um array
/// dentro do Plan, precisamente porque carrega a [UsageRule] específica
/// dessa combinação. Persistida como
/// `tenants/{tenantId}/plans/{planId}/services/{serviceId}` — o id do
/// documento é sempre igual ao [serviceId], por isso "que serviços este
/// Plan inclui" é uma leitura direta da subcoleção, sem query.
class PlanService extends Equatable {
  const PlanService({
    required this.planId,
    required this.serviceId,
    required this.enabled,
    required this.usage,
  });

  final String planId;
  final String serviceId;
  final bool enabled;
  final UsageRule usage;

  @override
  List<Object?> get props => [planId, serviceId, enabled, usage];
}
