import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../app.dart';
import '../../application/providers/firebase_providers.dart';
import '../../infrastructure/config/firebase_options_development.dart';
import '../../infrastructure/config/firebase_options_production.dart';
import '../../infrastructure/config/firebase_options_staging.dart';
import '../config/environment.dart';

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
    // Cloud Functions e Storage emulados são ligados aqui também, à medida
    // que os respetivos providers forem sendo criados (Fase 2+):
    //   FirebaseFunctions.instance.useFunctionsEmulator(host, port);
    //   FirebaseStorage.instance.useStorageEmulator(host, port);
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
