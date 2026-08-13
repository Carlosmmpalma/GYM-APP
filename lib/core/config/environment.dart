/// Ambientes suportados pela plataforma.
///
/// Corresponde à Fase 0 do guia de desenvolvimento: development / staging /
/// production, cada um potencialmente ligado a um Firebase Project distinto
/// (Platform Foundation §26 — CI/CD).
enum Environment {
  development,
  staging,
  production;

  bool get isDevelopment => this == Environment.development;
  bool get isStaging => this == Environment.staging;
  bool get isProduction => this == Environment.production;

  String get label => switch (this) {
        Environment.development => 'development',
        Environment.staging => 'staging',
        Environment.production => 'production',
      };
}

/// Configuração dependente do ambiente.
///
/// Nenhum valor aqui deve ser hardcoded fora deste ficheiro — se amanhã
/// surgir um novo ambiente, a alteração fica contida a esta classe.
class EnvironmentConfig {
  const EnvironmentConfig({
    required this.environment,
    required this.useFirestoreEmulator,
    required this.firestoreEmulatorHost,
    required this.firestoreEmulatorPort,
    required this.authEmulatorHost,
    required this.authEmulatorPort,
    required this.functionsEmulatorHost,
    required this.functionsEmulatorPort,
    required this.storageEmulatorHost,
    required this.storageEmulatorPort,
  });

  final Environment environment;

  /// Em desenvolvimento local, a app liga-se ao Firebase Emulator Suite
  /// (guia-desenvolvimento.md, Fase 0) em vez de um Firebase Project real.
  final bool useFirestoreEmulator;

  final String firestoreEmulatorHost;
  final int firestoreEmulatorPort;
  final String authEmulatorHost;
  final int authEmulatorPort;
  final String functionsEmulatorHost;
  final int functionsEmulatorPort;
  final String storageEmulatorHost;
  final int storageEmulatorPort;

  static const EnvironmentConfig development = EnvironmentConfig(
    environment: Environment.development,
    useFirestoreEmulator: true,
    firestoreEmulatorHost: 'localhost',
    firestoreEmulatorPort: 8080,
    authEmulatorHost: 'localhost',
    authEmulatorPort: 9099,
    functionsEmulatorHost: 'localhost',
    functionsEmulatorPort: 5001,
    storageEmulatorHost: 'localhost',
    storageEmulatorPort: 9199,
  );

  static const EnvironmentConfig staging = EnvironmentConfig(
    environment: Environment.staging,
    useFirestoreEmulator: false,
    firestoreEmulatorHost: '',
    firestoreEmulatorPort: 0,
    authEmulatorHost: '',
    authEmulatorPort: 0,
    functionsEmulatorHost: '',
    functionsEmulatorPort: 0,
    storageEmulatorHost: '',
    storageEmulatorPort: 0,
  );

  static const EnvironmentConfig production = EnvironmentConfig(
    environment: Environment.production,
    useFirestoreEmulator: false,
    firestoreEmulatorHost: '',
    firestoreEmulatorPort: 0,
    authEmulatorHost: '',
    authEmulatorPort: 0,
    functionsEmulatorHost: '',
    functionsEmulatorPort: 0,
    storageEmulatorHost: '',
    storageEmulatorPort: 0,
  );
}
