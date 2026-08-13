import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/member_summary.dart';
import '../../repositories/member_repository.dart';

MemberSummary _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return MemberSummary(
    uid: doc.id,
    memberNumber: data['memberNumber'] as String? ?? '',
    name: data['name'] as String? ?? '(sem nome)',
    active: (data['status'] as String? ?? 'active') == 'active',
  );
}

class FirebaseMemberRepository implements MemberRepository {
  FirebaseMemberRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  @override
  Stream<List<MemberSummary>> watchMembers() {
    return _firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }
}
