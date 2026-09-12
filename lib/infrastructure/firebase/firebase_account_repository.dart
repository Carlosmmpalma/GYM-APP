import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/app_user.dart';
import '../../repositories/account_repository.dart';

/// Um utilizador pode ter documento em `members/`, em `staff/`, ou em
/// ambos (Domain Model v1 §6 — instrutor que também é membro). Para a
/// flag de password temporária, basta que UM dos dois esteja marcado.
///
/// Implementação escolhe usar o Firebase `uid` como ID do documento em
/// `members/{uid}` / `staff/{uid}` (o Firestore Data Model v1 §7 permite
/// isto — "memberId não precisa obrigatoriamente de ser igual ao uid",
/// não proíbe que seja). Isto evita uma query por campo + índice
/// composto só para um lookup que a Cloud Function `createMember`/
/// `createStaff` já sabe fazer diretamente.
class FirebaseAccountRepository implements AccountRepository {
  FirebaseAccountRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _memberDoc(AppUser user) => _firestore
      .collection('tenants')
      .doc(user.tenantId)
      .collection('members')
      .doc(user.uid);

  DocumentReference<Map<String, dynamic>> _staffDoc(AppUser user) => _firestore
      .collection('tenants')
      .doc(user.tenantId)
      .collection('staff')
      .doc(user.uid);

  /// Os documentos desta pessoa — só onde ela pode mesmo existir.
  ///
  /// Lia sempre os DOIS. Para um aluno, a leitura de `staff/{uid}` nunca
  /// devolvia nada: uma ida ao servidor garantidamente falhada em cada
  /// arranque da app, num sítio onde o utilizador está a olhar para um
  /// ecrã de espera. Os roles vêm no token e dizem exatamente onde
  /// procurar.
  ///
  /// Se o token vier sem roles (não devia acontecer, mas um token velho
  /// ou uma conta meio criada chegam para isso), procura nos dois — mais
  /// vale pagar a leitura do que decidir com base em nada.
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _findDocs(
    AppUser user,
  ) async {
    final isStaff = user.isManager || user.isInstructor;
    final refs = <DocumentReference<Map<String, dynamic>>>[
      if (user.isMember) _memberDoc(user),
      if (isStaff) _staffDoc(user),
      if (!user.isMember && !isStaff) ...[_memberDoc(user), _staffDoc(user)],
    ];

    final results = await Future.wait(refs.map((ref) => ref.get()));
    return results.where((doc) => doc.exists).toList();
  }

  @override
  Future<bool> hasTemporaryPassword(AppUser user) async {
    final docs = await _findDocs(user);
    return docs.any((doc) => doc.data()?['passwordTemporaria'] == true);
  }

  @override
  Future<void> clearTemporaryPasswordFlag(AppUser user) async {
    final docs = await _findDocs(user);
    final batch = _firestore.batch();
    for (final doc in docs) {
      batch.update(doc.reference, {'passwordTemporaria': false});
    }
    await batch.commit();
  }
}
