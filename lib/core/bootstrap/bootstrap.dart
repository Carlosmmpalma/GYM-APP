import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
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

/// Ativa o App Check com o provider certo para a plataforma e o
/// ambiente. Nunca deixa o arranque falhar: um dispositivo que não
/// consiga atestar (emulador de Android sem Play Services, por exemplo)
/// deve entrar na app à mesma enquanto o `enforcement` estiver
/// desligado no servidor — falhar aqui seria trocar um risco de abuso
/// por uma app que não abre.
Future<void> _activateAppCheck(EnvironmentConfig config) async {
  try {
    await FirebaseAppCheck.instance.activate(
      // Web em produção precisa de uma reCAPTCHA v3 site key gerada na
      // Firebase Console; até existir, fica o debug provider, que só
      // funciona com tokens registados à mão. Ver checklist do README.
      webProvider: config.recaptchaSiteKey == null
          ? ReCaptchaV3Provider('debug')
          : ReCaptchaV3Provider(config.recaptchaSiteKey!),
      androidProvider: config.environment.isProduction
          ? AndroidProvider.playIntegrity
          : AndroidProvider.debug,
      appleProvider: config.environment.isProduction
          ? AppleProvider.appAttest
          : AppleProvider.debug,
    );
  } catch (error, stack) {
    // Só regista — ver docstring.
    debugPrint('App Check não ativou: $error\n$stack');
  }
}

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

  // Cache offline do Firestore (Fase 11).
  //
  // Estava desligado, e é das poucas coisas de infraestrutura que se
  // ganham com uma linha. Num ginásio — cave, paredes de betão, wifi
  // partilhado com a aparelhagem — a ligação cai a meio de tudo. Com
  // cache, o que já foi lido continua a aparecer, e as escritas diretas
  // ao Firestore ficam em fila até haver rede.
  //
  // O que isto NÃO resolve, e é bom não confundir: as Cloud Functions
  // (marcar, cancelar, criar utilizadores) precisam mesmo de rede — não
  // há como pôr em fila uma transação que valida capacidade contra o
  // estado do servidor. Essas continuam a falhar sem ligação, agora com
  // uma mensagem que o diz (ver `describeFirebaseError`).
  //
  // Em Web a persistência é opt-in e falha se houver várias abas
  // abertas; daí o `try`. Falhar aqui nunca deve impedir o arranque.
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (error) {
    debugPrint('Cache offline do Firestore não ativou: $error');
  }

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
    FirebaseFunctions.instanceFor(region: kFunctionsRegion)
        .useFunctionsEmulator(
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

  // App Check (Fase 11) — atesta que quem chama vem MESMO da nossa app.
  //
  // A `apiKey` do Firebase é pública (vai no bundle web, extrai-se de um
  // APK): sem isto, qualquer pessoa chama `createBooking` ou
  // `createMember` por HTTP direto, fora da app. As Security Rules e os
  // guards de role continuam a decidir QUEM pode fazer o quê — o que
  // falta é impedir um script de martelar as funções e gerar custo. O
  // pacote `firebase_app_check` estava no pubspec desde a Fase 0 e nunca
  // tinha sido inicializado; via-se nos logs do emulador
  // (`"verifications":{"app":"MISSING"}`).
  //
  // Em desenvolvimento usamos os debug providers: imprimem um token na
  // consola que tem de ser registado na Firebase Console para o projeto
  // real. Contra o emulador nada disto é verificado, por isso não
  // atrapalha o ciclo local.
  //
  // `enforcement` NÃO está ligado por omissão do lado do servidor: até
  // se ativar na consola, o App Check só MONITORIZA. Ver o checklist de
  // lançamento no README — é intencional que se comece por monitorizar,
  // para não bloquear utilizadores reais por um dispositivo mal atestado.
  //
  // NÃO se espera por isto. Na web, ativar o App Check carrega o script
  // do reCAPTCHA a partir da rede — e enquanto esse pedido não
  // resolvesse, a app não chegava a arrancar. Bastava a rede estar
  // lenta, ou um bloqueador de anúncios travar o pedido, para o ecrã
  // ficar em branco e parecer que "não dá para entrar".
  //
  // Os tokens do App Check são anexados aos pedidos conforme vão sendo
  // precisos; não há nada que exija tê-lo pronto antes do primeiro
  // fotograma.
  unawaited(_activateAppCheck(config));

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
