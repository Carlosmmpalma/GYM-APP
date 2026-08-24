import '../domain/entities/retention_overview.dart';

/// Fase 11 — painel de retenção do Gestor.
abstract class RetentionRepository {
  /// [windowDays] governa as taxas (ocupação, faltas); [riskWeeks] o
  /// corte a partir do qual alguém conta como "não aparece há muito".
  Future<RetentionOverview> getOverview({
    int windowDays = 30,
    int riskWeeks = 3,
  });
}
