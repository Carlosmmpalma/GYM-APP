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

  /// Fase 8 (auditoria funcional, UC06/UC07/UC08/UC09 fechado) —
  /// "antecedência mínima para MARCAR" (não confundir com
  /// [getMinCancellationNoticeHours], que é sobre cancelar). Mesmo
  /// documento (`tenants/{tenantId}/config/bookingPolicy`), campo
  /// irmão `minBookingNoticeMinutes`. Só se aplica a marcação
  /// self-service (`createBooking`/`bookFreeTrainingSlot`) — atribuição
  /// manual por Instrutor/Gestor nunca passa por esta validação, mesmo
  /// espírito de UC08-A. `0` (sem restrição) se o documento ainda não
  /// existir.
  Future<int> getMinBookingNoticeMinutes(String tenantId);

  Future<void> setMinBookingNoticeMinutes({
    required String tenantId,
    required int minutes,
  });
}
