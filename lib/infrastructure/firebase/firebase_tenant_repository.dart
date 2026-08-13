import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/tenant.dart';
import '../../repositories/tenant_repository.dart';

class FirebaseTenantRepository implements TenantRepository {
  FirebaseTenantRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Tenant?> getTenant(String tenantId) async {
    final snapshot = await _firestore.collection('tenants').doc(tenantId).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data()!;
    return Tenant(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      timezone: data['timezone'] as String? ?? 'Europe/Lisbon',
      status: (data['status'] as String? ?? 'active') == 'active'
          ? TenantStatus.active
          : TenantStatus.suspended,
    );
  }

  DocumentReference<Map<String, dynamic>> _bookingPolicyDoc(String tenantId) =>
      _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('config')
          .doc('bookingPolicy');

  @override
  Future<int> getMinCancellationNoticeHours(String tenantId) async {
    final snapshot = await _bookingPolicyDoc(tenantId).get();
    if (!snapshot.exists) return 0;
    return (snapshot.data()?['minCancellationNoticeHours'] as num? ?? 0).toInt();
  }

  @override
  Future<void> setMinCancellationNoticeHours({
    required String tenantId,
    required int hours,
  }) async {
    await _bookingPolicyDoc(tenantId).set({
      'minCancellationNoticeHours': hours,
    }, SetOptions(merge: true));
  }
}
