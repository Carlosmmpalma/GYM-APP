/// O que se pode eliminar do catálogo do estúdio.
enum CatalogueKind {
  service('service'),
  plan('plan'),
  modality('modality'),
  exercise('exercise'),
  series('series'),
  staff('staff'),
  occurrence('occurrence'),
  exerciseCategory('exerciseCategory'),
  freeTrainingWeek('freeTrainingWeek');

  const CatalogueKind(this.wireName);

  /// O que a Cloud Function espera receber.
  final String wireName;
}

/// Lançada quando há coisas a depender do que se tentou eliminar.
///
/// Carrega a lista do que bloqueia — em português, já formatada pelo
/// servidor — porque "não dá para eliminar" sem dizer porquê é a
/// diferença entre o Gestor resolver sozinho e ligar a alguém.
class CatalogueEntryInUseException implements Exception {
  const CatalogueEntryInUseException(this.blockers);

  final List<String> blockers;

  @override
  String toString() => 'CatalogueEntryInUseException($blockers)';
}

/// Eliminar serviços, planos e modalidades.
///
/// Vive num repositório próprio, e não em `ServiceRepository`/
/// `PlanRepository`/`ModalityRepository`, porque é uma operação só: a
/// mesma Cloud Function, a mesma verificação, a mesma recusa. Espalhá-la
/// pelos três obrigaria a dar `FirebaseFunctions` a repositórios que
/// hoje só falam com o Firestore, e a atualizar todos os seus fakes,
/// para acabar com três cópias da mesma coisa.
abstract class CatalogueAdminRepository {
  /// Lança [CatalogueEntryInUseException] quando alguma coisa depende
  /// desta entrada. O servidor é quem decide — a UI pode esconder o
  /// botão, mas nunca é ela a garantir nada.
  Future<void> delete({required CatalogueKind kind, required String id});
}
