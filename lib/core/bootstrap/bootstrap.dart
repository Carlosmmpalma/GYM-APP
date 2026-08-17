import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../app.dart';
import '../../application/providers/firebase_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../infrastructure/config/firebase_options_development.dart';
import '../../infrastructure/config/firebase_options_production.dart';
import '../../infrastructure/config/firebase_options_staging.dart';
import '../config/environment.dart';
import '../config/tenant_app_config.dart';

/// Ponto de entrada único, chamado por main_development.dart,
/// main_staging.dart e main_production.dart (guia-desenvolvimento.md,
/// Fase 0 — "Configurar ambientes development/staging/production").
///
/// Nenhum destes três main_*.dart deve conter lógica além de escolher o
/// ambiente e chamar esta função.
Future<void> bootstrap(Environment environment) async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = switch (environment) {
    Environment.development => EnvironmentConfig.development,
    Environment.staging => EnvironmentConfig.staging,
    Environment.production => EnvironmentConfig.production,
  };

  final firebaseOptions = switch (environment) {
    Environment.development => DevelopmentFirebaseOptions.currentPlatform,
    Environment.staging => StagingFirebaseOptions.currentPlatform,
    Environment.production => ProductionFirebaseOptions.currentPlatform,
  };

  final tenantAppConfig = switch (environment) {
    Environment.development => TenantAppConfig.development,
    Environment.staging => TenantAppConfig.staging,
    Environment.production => TenantAppConfig.production,
  };

  // Necessário antes de qualquer DateFormat com locale 'pt_PT' (ver
  // presentation/screens/book_training_screen.dart) — sem isto, o intl
  // lança LocaleDataException em runtime na primeira formatação de data.
  await initializeDateFormatting('pt_PT');

  await Firebase.initializeApp(options: firebaseOptions);

  if (config.useFirestoreEmulator) {
    FirebaseFirestore.instance.useFirestoreEmulator(
      config.firestoreEmulatorHost,
      config.firestoreEmulatorPort,
    );
    await FirebaseAuth.instance.useAuthEmulator(
      config.authEmulatorHost,
      config.authEmulatorPort,
    );
    // Fase 3 — createSubscription é a primeira Cloud Function chamada
    // diretamente pela app (createMember/createStaff, da Fase 1, só são
    // chamadas pelo seed script via Admin SDK, nunca pelo cliente).
    FirebaseFunctions.instance.useFunctionsEmulator(
      config.functionsEmulatorHost,
      config.functionsEmulatorPort,
    );
    // Fase 8 — primeiro provider a precisar mesmo de Storage
    // (`FirebaseStorageRepository`, vídeo de exercícios, UC15).
    await FirebaseStorage.instance.useStorageEmulator(
      config.storageEmulatorHost,
      config.storageEmulatorPort,
    );
  }

  // Crashlytics (Platform Foundation §24 — Observabilidade). Em
  // development contra o emulador isto reporta para um Firebase Project
  // "demo-*" que não existe na cloud — o SDK aceita isto sem erro, mas os
  // relatórios não vão a lado nenhum. Só passa a ter efeito real quando
  // firebase_options_development/staging/production apontarem para um
  // projeto real.
  if (!kDebugMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runZonedGuarded(
    () => runApp(
      ProviderScope(
        overrides: [
          environmentConfigProvider.overrideWithValue(config),
          tenantAppConfigProvider.overrideWithValue(tenantAppConfig),
        ],
        child: const GymSaasApp(),
      ),
    ),
    (error, stack) {
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } else {
        // ignore: avoid_print
        print('Uncaught error in $environment: $error\n$stack');
      }
    },
  );
}
