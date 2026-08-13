import '../../domain/entities/ping_result.dart';
import '../../repositories/ping_repository.dart';

/// Use case da camada Application (Platform Foundation §10).
///
/// Orquestra a chamada ao repository. Neste caso é trivial de propósito —
/// serve só para provar que a fatia Presentation → Application →
/// Repositories → Infrastructure está ligada ponta a ponta antes de
/// construir lógica de negócio real.
class PingFirestoreUseCase {
  const PingFirestoreUseCase(this._repository);

  final PingRepository _repository;

  Future<PingResult> call(String message) => _repository.writePing(message);
}
