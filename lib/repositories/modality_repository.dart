import '../domain/entities/modality.dart';

/// Fase 6 — mesmo padrão de `ServiceRepository`: CRUD simples, escrita
/// direta do cliente (Manager), sem nenhuma invariante cross-documento
/// a proteger.
abstract class ModalityRepository {
  Stream<List<Modality>> watchModalities();

  /// Devolve o id do documento criado.
  Future<String> createModality({required String name});

  Future<void> setModalityActive({
    required String modalityId,
    required bool active,
  });

  /// Liga/desliga um serviço a esta modalidade — mesmo espírito de
  /// `PlanRepository.setPlanService`, mas aqui a lista inteira vive no
  /// próprio documento da modalidade (ver nota em `modality.dart`).
  Future<void> setServiceEnabled({
    required String modalityId,
    required String serviceId,
    required bool enabled,
  });
}
