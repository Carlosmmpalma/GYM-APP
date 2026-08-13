// PLACEHOLDER — substituir pelo output real de `flutterfire configure`.
//
// Ao contrário do ambiente de development, staging e production ligam-se
// a Firebase Projects reais (Platform Foundation §26 — CI/CD:
// development / staging / production não devem partilhar projeto nem
// credenciais). Eu não tenho acesso à tua conta Google Cloud/Firebase,
// por isso não posso criar este projeto nem gerar as credenciais reais.
//
// Passos manuais:
//   1. Criar o Firebase Project "gym-saas-staging" (ou nome equivalente)
//      na consola Firebase.
//   2. dart pub global activate flutterfire_cli
//   3. flutterfire configure --project=<id-do-projeto-staging> \
//        --out=lib/infrastructure/config/firebase_options_staging.dart

import 'package:firebase_core/firebase_core.dart';

class StagingFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'firebase_options_staging.dart ainda não foi gerado. '
      'Ver comentário no topo deste ficheiro.',
    );
  }
}
