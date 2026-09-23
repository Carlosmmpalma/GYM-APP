import '../domain/entities/service.dart';

abstract class ServiceRepository {
  Future<List<Service>> getActiveServices();

  /// Fase 3 (UC26) — todos os Services do tenant (ativos e inativos),
  /// para o ecrã de gestão. `getActiveServices()` continua a existir
  /// separado porque é usado pelo fluxo de booking (Fase 2), que só
  /// alguma vez deve mostrar Services ativos.
  Stream<List<Service>> watchServices();

  /// Devolve o id do documento criado.
  ///
  /// Um serviço é só um nome. Teve um `exclusiveGroup` — uma etiqueta
  /// de texto livre que declarava quais eram alternativas uns dos
  /// outros — e essa ideia desapareceu com a passagem a **um plano
  /// ativo por membro**: sem dois planos ao mesmo tempo, não há
  /// combinações para proibir. Ver `createSubscription.ts`.
  Future<String> createService({required String name});

  Future<void> setServiceActive({
    required String serviceId,
    required bool active,
  });

  /// Editar o nome de um serviço já criado. Nunca toca em `active`
  /// (isso é [setServiceActive], ação já isolada e com o seu próprio
  /// switch).
  Future<void> updateService({
    required String serviceId,
    required String name,
  });
}
