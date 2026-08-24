import 'package:cloud_functions/cloud_functions.dart';

import '../../repositories/catalogue_admin_repository.dart';

class FirebaseCatalogueAdminRepository implements CatalogueAdminRepository {
  FirebaseCatalogueAdminRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> delete({
    required CatalogueKind kind,
    required String id,
  }) async {
    try {
      await _functions.httpsCallable('deleteCatalogueEntry').call<Object?>({
        'kind': kind.wireName,
        'id': id,
      });
    } on FirebaseFunctionsException catch (e) {
      // A função devolve a lista do que bloqueia em `details.blockers`.
      // Sem ela, o ecrã só conseguiria dizer "não dá" — que é
      // exatamente a mensagem que obriga alguém a pedir ajuda.
      if (e.code == 'failed-precondition') {
        final details = e.details;
        final blockers = details is Map ? details['blockers'] : null;
        if (blockers is List) {
          throw CatalogueEntryInUseException(
            blockers.map((b) => b.toString()).toList(),
          );
        }
      }
      rethrow;
    }
  }
}
