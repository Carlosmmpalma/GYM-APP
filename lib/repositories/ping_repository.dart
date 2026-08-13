import '../domain/entities/ping_result.dart';

/// Interface consumida pela camada de Application/Presentation.
///
/// A camada acima desta nunca deve conhecer Firestore diretamente
/// (Platform Foundation §11 — "Firebase não deve estar espalhado pela
/// aplicação"). Só a implementação concreta em `infrastructure/` sabe que
/// está a falar com o Firestore.
abstract class PingRepository {
  Future<PingResult> writePing(String message);
  Future<PingResult?> readLastPing();
}
