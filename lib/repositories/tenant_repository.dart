import '../domain/entities/tenant.dart';

abstract class TenantRepository {
  Future<Tenant?> getTenant(String tenantId);

  /// Fase 4 — "Cancelamento devolve usage se dentro da janela permitida
  /// (antecedência mínima)". Decisão (Carlos): um único valor por
  /// tenant, não por Plan/Service. Lido de
  /// `tenants/{tenantId}/config/bookingPolicy`; `0` (sem restrição) se
  /// o documento ainda não existir — é o default seguro: não bloqueia
  /// nada até o Gestor configurar explicitamente um valor.
  Future<int> getMinCancellationNoticeHours(String tenantId);

  /// Só chamável pelo Gestor (Security Rules: `config/{configId}`
  /// exige `isManager`).
  Future<void> setMinCancellationNoticeHours({
    required String tenantId,
    required int hours,
  });
}
