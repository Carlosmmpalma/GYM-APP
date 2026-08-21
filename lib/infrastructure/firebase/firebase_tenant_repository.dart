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
    return (snapshot.data()?['minCancellationNoticeHours'] as num? ?? 0)
        .toInt();
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

  @override
  Future<int> getMinBookingNoticeMinutes(String tenantId) async {
    final snapshot = await _bookingPolicyDoc(tenantId).get();
    if (!snapshot.exists) return 0;
    return (snapshot.data()?['minBookingNoticeMinutes'] as num? ?? 0).toInt();
  }

  @override
  Future<void> setMinBookingNoticeMinutes({
    required String tenantId,
    required int minutes,
  }) async {
    await _bookingPolicyDoc(tenantId).set({
      'minBookingNoticeMinutes': minutes,
    }, SetOptions(merge: true));
  }

  @override
  Future<String?> getFreeTrainingServiceId(String tenantId) async {
    final snapshot = await _bookingPolicyDoc(tenantId).get();
    if (!snapshot.exists) return null;
    final value = snapshot.data()?['freeTrainingServiceId'] as String?;
    // String vazia conta como não configurado — é o que fica se alguém
    // limpar o campo em vez de o apagar.
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> setFreeTrainingServiceId({
    required String tenantId,
    required String? serviceId,
  }) async {
    await _bookingPolicyDoc(tenantId).set({
      'freeTrainingServiceId': serviceId ?? '',
    }, SetOptions(merge: true));
  }
}
