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
  /// [exclusiveGroup] — UC26 (fechado): identificador livre partilhado
  /// por serviços mutuamente exclusivos (ex.: "sala" em "Sem
  /// acompanhamento" e no serviço que Standard/Plus/Premium concedem).
  /// `null` (omisso) para serviços sem essa restrição.
  Future<String> createService({required String name, String? exclusiveGroup});

  Future<void> setServiceActive({
    required String serviceId,
    required bool active,
  });

  /// Fase 8 (auditoria funcional) — editar nome/`exclusiveGroup` de um
  /// serviço já criado. Nunca toca em `active` (isso é
  /// [setServiceActive], ação já isolada e com o seu próprio switch).
  Future<void> updateService({
    required String serviceId,
    required String name,
    String? exclusiveGroup,
  });
}
