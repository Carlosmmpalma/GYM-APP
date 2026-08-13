// Teste de integração REAL contra o Firebase Emulator Suite — é este
// ficheiro que efetivamente comprova o critério "Done" da Fase 0
// (guia-desenvolvimento.md): "app Flutter arranca, liga ao emulador
// local, e um hello world lê/escreve um documento de teste no Firestore
// emulado".
//
// Os testes em test/ usam fakes/mocks e correm em qualquer máquina sem
// setup adicional. Este teste é diferente: usa cloud_firestore a sério,
// por isso precisa de:
//   1. um dispositivo/emulador Android, simulador iOS, Chrome ou desktop
//      a correr (integration_test usa platform channels reais);
//   2. o Firebase Emulator Suite a correr em paralelo:
//        firebase emulators:start --only firestore,auth
//
// Corre com:
//   flutter test integration_test/emulator_smoke_test.dart -d <device-id>
//
// Não corri este teste neste ambiente — não tenho Flutter SDK nem
// dispositivo disponíveis aqui (ver README.md, secção "Limitações").

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/infrastructure/config/firebase_options_development.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_ping_repository.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('escreve e lê um documento real no Firestore emulado',
      (tester) async {
    await Firebase.initializeApp(
      options: DevelopmentFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

    final repository = FirebasePingRepository(FirebaseFirestore.instance);

    final written = await repository.writePing('integration test ping');
    final read = await repository.readLastPing();

    expect(read, isNotNull);
    expect(read!.message, written.message);
  });
}
