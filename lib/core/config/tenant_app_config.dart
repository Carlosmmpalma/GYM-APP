/// Qual tenant esta build da app serve.
///
/// Platform Foundation §13 define que branding/regras pertencem ao
/// tenant e não devem ser hardcoded — mas ALGUÉM tem de dizer à app, no
/// arranque, "estás a servir o tenant X" antes de qualquer login
/// acontecer (a resolução completa por subdomínio/config remota é
/// trabalho futuro; para o cliente 0 um valor fixo por ambiente chega).
///
/// Este `tenantId` é o mesmo usado no seed script
/// (firebase/scripts/seed.ts) e nas Security Rules
/// (`tenants/{tenantId}/...`).
class TenantAppConfig {
  const TenantAppConfig({required this.tenantId});

  final String tenantId;

  static const TenantAppConfig development = TenantAppConfig(
    tenantId: 'nxt_performance_studio',
  );

  // staging/production: substituir quando os respetivos tenants forem
  // criados. Por agora apontam para o mesmo tenant de development —
  // ajustar assim que houver um Firebase Project de staging/production
  // real (ver lib/infrastructure/config/firebase_options_*.dart).
  static const TenantAppConfig staging = TenantAppConfig(
    tenantId: 'nxt_performance_studio',
  );

  static const TenantAppConfig production = TenantAppConfig(
    tenantId: 'nxt_performance_studio',
  );
}
