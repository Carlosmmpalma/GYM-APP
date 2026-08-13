import '../domain/entities/plan.dart';
import '../domain/entities/plan_service.dart';
import '../domain/entities/usage_rule.dart';

/// Fase 3 (guia-desenvolvimento.md) — Repository Pattern (Platform
/// Foundation §12): a camada de aplicação só conhece esta interface.
abstract class PlanRepository {
  Stream<List<Plan>> watchPlans();

  Future<List<PlanService>> getPlanServices(String planId);

  /// Devolve o id do documento criado.
  Future<String> createPlan({
    required String name,
    required String description,
    required double currentPrice,
    required String currency,
  });

  Future<void> updatePlan(Plan plan);

  /// Cria ou atualiza a relação Plan↔Service (documento com id ==
  /// [serviceId] — ver nota em `plan_service.dart`).
  Future<void> setPlanService({
    required String planId,
    required String serviceId,
    required bool enabled,
    required UsageRule usage,
  });
}
