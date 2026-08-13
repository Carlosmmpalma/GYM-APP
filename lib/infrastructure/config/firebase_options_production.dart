// PLACEHOLDER — substituir pelo output real de `flutterfire configure`.
//
// Ver firebase_options_staging.dart para o racional. Para produção, o
// Firebase Project deve ser criado com o máximo cuidado (billing, App
// Check, Security Rules revistas) antes de gerar estas credenciais —
// não faças isto até o documento "06 — Security & Business Rules" e as
// Security Rules estarem completas e testadas (guia-desenvolvimento.md,
// Fase 10).
//
//   flutterfire configure --project=<id-do-projeto-production> \
//       --out=lib/infrastructure/config/firebase_options_production.dart

import 'package:firebase_core/firebase_core.dart';

class ProductionFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'firebase_options_production.dart ainda não foi gerado. '
      'Ver comentário no topo deste ficheiro.',
    );
  }
}
