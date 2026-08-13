// Opções do Firebase para o ambiente de DESENVOLVIMENTO LOCAL.
//
// Usa um projectId com o prefixo "demo-", que o Firebase Emulator Suite
// trata como um projeto local sem qualquer ligação à cloud real
// (documentado pela própria Firebase: projectIds "demo-*" nunca tentam
// contactar backends reais, mesmo que os restantes campos sejam fictícios).
// Isto permite satisfazer o critério "Done" da Fase 0 — app liga ao
// emulador e lê/escreve um documento de teste — sem precisares de criar
// já um Firebase Project real na consola.
//
// Quando quiseres testar contra um Firebase Project de development real
// (não emulado), substitui este ficheiro pelo gerado por:
//   flutterfire configure --project=<id-real-de-development>

import 'package:firebase_core/firebase_core.dart';

class DevelopmentFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-gym-saas-dev',
    storageBucket: 'demo-gym-saas-dev.appspot.com',
  );
}
