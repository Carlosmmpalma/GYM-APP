/// Região onde as Cloud Functions estão implantadas.
///
/// Tem de ser a MESMA que `setGlobalOptions` declara em
/// `firebase/functions/src/index.ts`. Se divergirem, o cliente chama
/// `us-central1`, onde não existe nada, e todas as funções falham com
/// `not-found` — um erro que não deixa perceber que o problema é
/// geográfico. Daí a constante estar num sítio só.
const String kFunctionsRegion = 'europe-west1';

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
    this.recaptchaSiteKey,
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

  /// Site key do reCAPTCHA v3, para o App Check na web (Fase 11).
  ///
  /// `null` = ainda não existe (é gerada na Firebase Console, por
  /// projeto) e o arranque usa o debug provider. Não é segredo — vai no
  /// bundle web de qualquer forma, tal como a `apiKey`.
  final String? recaptchaSiteKey;

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
