import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/ping_firestore_use_case.dart';
import 'package:gym_saas/domain/entities/ping_result.dart';
import 'package:gym_saas/repositories/ping_repository.dart';

/// Fake escrito à mão em vez de mocktail: o use case é trivial e um fake
/// deixa claro o comportamento sem "when()/thenAnswer()" desnecessário.
class _FakePingRepository implements PingRepository {
  String? lastWrittenMessage;

  @override
  Future<PingResult> writePing(String message) async {
    lastWrittenMessage = message;
    return PingResult(id: 'fake', message: message, recordedAt: DateTime(2026));
  }

  @override
  Future<PingResult?> readLastPing() async {
    if (lastWrittenMessage == null) return null;
    return PingResult(
      id: 'fake',
      message: lastWrittenMessage!,
      recordedAt: DateTime(2026),
    );
  }
}

void main() {
  test('PingFirestoreUseCase delega no repository sem alterar a mensagem',
      () async {
    final repository = _FakePingRepository();
    final useCase = PingFirestoreUseCase(repository);

    final result = await useCase('olá emulador');

    expect(result.message, 'olá emulador');
    expect(repository.lastWrittenMessage, 'olá emulador');
  });
}
