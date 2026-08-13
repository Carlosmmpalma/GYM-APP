import '../domain/entities/service.dart';

abstract class ServiceRepository {
  Future<List<Service>> getActiveServices();

  /// Fase 3 (UC26) — todos os Services do tenant (ativos e inativos),
  /// para o ecrã de gestão. `getActiveServices()` continua a existir
  /// separado porque é usado pelo fluxo de booking (Fase 2), que só
  /// alguma vez deve mostrar Services ativos.
  Stream<List<Service>> watchServices();

  /// Devolve o id do documento criado.
  Future<String> createService({required String name});

  Future<void> setServiceActive({
    required String serviceId,
    required bool active,
  });
}
