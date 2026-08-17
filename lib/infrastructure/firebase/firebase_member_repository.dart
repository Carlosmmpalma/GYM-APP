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
    phone: data['phone'] as String? ?? '',
    email: data['email'] as String? ?? '',
    birthDate: (data['birthDate'] as Timestamp?)?.toDate(),
    address: data['address'] as String? ?? '',
    nif: data['nif'] as String? ?? '',
    emergencyContact: data['emergencyContact'] as String? ?? '',
  );
}

class FirebaseMemberRepository implements MemberRepository {
  FirebaseMemberRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _members =>
      _firestore.collection('tenants').doc(_tenantId).collection('members');

  @override
  Stream<List<MemberSummary>> watchMembers() {
    return _members
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Stream<MemberSummary?> watchMember(String memberId) {
    return _members.doc(memberId).snapshots().map(
          (snapshot) => snapshot.exists ? _fromDoc(snapshot) : null,
        );
  }

  @override
  Future<void> setMemberActive({
    required String memberId,
    required bool active,
  }) async {
    await _members.doc(memberId).update({
      'status': active ? 'active' : 'inactive',
    });
  }

  @override
  Future<void> updateOwnContact({
    required String memberId,
    required String phone,
    required String email,
  }) async {
    await _members.doc(memberId).update({
      'phone': phone,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> registerFcmToken({
    required String memberId,
    required String token,
  }) async {
    await _members.doc(memberId).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  @override
  Future<void> updateMemberProfile({
    required String memberId,
    required String name,
    required String phone,
    required String email,
    DateTime? birthDate,
    required String address,
    required String nif,
    required String emergencyContact,
  }) async {
    await _members.doc(memberId).update({
      'name': name,
      'phone': phone,
      'email': email,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate) : null,
      'address': address,
      'nif': nif,
      'emergencyContact': emergencyContact,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
