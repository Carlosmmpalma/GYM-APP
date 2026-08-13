import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_ping_repository.dart';

/// Testa a implementação real do repository contra um Firestore fake
/// em memória (fake_cloud_firestore), sem depender do emulador nem de
/// Firebase.initializeApp(). Isto cobre a lógica de leitura/escrita;
/// não substitui o teste de integração contra o emulador real descrito
/// no critério "Done" da Fase 0.
void main() {
  test('writePing depois readLastPing devolve a última mensagem escrita',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repository = FirebasePingRepository(firestore);

    await repository.writePing('primeira mensagem');
    await repository.writePing('segunda mensagem');

    final last = await repository.readLastPing();

    expect(last, isNotNull);
    expect(last!.message, 'segunda mensagem');
  });

  test('readLastPing devolve null se ainda não houver nenhum ping', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = FirebasePingRepository(firestore);

    final result = await repository.readLastPing();

    expect(result, isNull);
  });
}
