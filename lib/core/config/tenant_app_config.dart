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
  const TenantAppConfig({
    required this.tenantId,
    this.displayName,
    this.logoAsset,
  });

  final String tenantId;

  /// Nome comercial do estúdio, para o ecrã de login (Fase 10).
  ///
  /// O documento `tenants/{id}` já tem um `name`, mas não serve aqui: as
  /// Security Rules exigem sessão para o ler, e este ecrã é exatamente o
  /// que se vê ANTES de haver sessão. Branding é, por isso, config de
  /// build — que é também onde o Platform Foundation §13 o coloca.
  /// `null` (o caso dos testes) simplesmente não desenha o nome, em vez
  /// de mostrar o `tenantId` cru.
  final String? displayName;

  /// Logótipo do estúdio (asset da build), mostrado no login. Mesma
  /// razão de [displayName] para ser config e não um ficheiro no
  /// Storage do tenant: este ecrã aparece antes de haver sessão, e sem
  /// sessão não há leitura autorizada de nada do tenant. `null` cai no
  /// [displayName] em texto.
  final String? logoAsset;

  static const TenantAppConfig development = TenantAppConfig(
    tenantId: 'nxt_performance_studio',
    displayName: 'NXT Performance Studio',
    logoAsset: 'assets/branding/logo_wordmark.png',
  );

  // staging/production: substituir quando os respetivos tenants forem
  // criados. Por agora apontam para o mesmo tenant de development —
  // ajustar assim que houver um Firebase Project de staging/production
  // real (ver lib/infrastructure/config/firebase_options_*.dart).
  static const TenantAppConfig staging = TenantAppConfig(
    tenantId: 'nxt_performance_studio',
    displayName: 'NXT Performance Studio',
    logoAsset: 'assets/branding/logo_wordmark.png',
  );

  static const TenantAppConfig production = TenantAppConfig(
    tenantId: 'nxt_performance_studio',
    displayName: 'NXT Performance Studio',
    logoAsset: 'assets/branding/logo_wordmark.png',
  );
}
