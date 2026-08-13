import '../domain/entities/tenant.dart';

abstract class TenantRepository {
  Future<Tenant?> getTenant(String tenantId);
}
