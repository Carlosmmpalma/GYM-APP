import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/role.dart';
import '../../domain/entities/staff_summary.dart';
import '../../repositories/staff_repository.dart';

StaffSummary _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? const {};
  final rolesRaw = (data['roles'] as List?) ?? const [];
  return StaffSummary(
    uid: doc.id,
    name: data['name'] as String? ?? '(sem nome)',
    email: data['email'] as String? ?? '',
    roles: rolesRaw.map((r) => Role.fromClaim(r as String)).toSet(),
    active: (data['status'] as String? ?? 'active') == 'active',
  );
}

class FirebaseStaffRepository implements StaffRepository {
  FirebaseStaffRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _staff =>
      _firestore.collection('tenants').doc(_tenantId).collection('staff');

  @override
  Stream<List<StaffSummary>> watchStaff() {
    return _staff.snapshots().map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList(),
        );
  }

  @override
  Future<void> setStaffActive({
    required String staffId,
    required bool active,
  }) async {
    await _staff.doc(staffId).update({
      'status': active ? 'active' : 'inactive',
    });
  }
}
