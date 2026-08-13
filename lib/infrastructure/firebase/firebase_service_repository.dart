import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/service.dart';
import '../../repositories/service_repository.dart';

Service _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? const {};
  return Service(
    id: doc.id,
    name: data['name'] as String? ?? '',
    active: data['active'] as bool? ?? false,
  );
}

class FirebaseServiceRepository implements ServiceRepository {
  FirebaseServiceRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _services => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('services');

  @override
  Future<List<Service>> getActiveServices() async {
    final snapshot = await _services.where('active', isEqualTo: true).get();
    return snapshot.docs.map(_fromDoc).toList();
  }

  @override
  Stream<List<Service>> watchServices() {
    return _services.snapshots().map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList(),
        );
  }

  @override
  Future<String> createService({required String name}) async {
    final ref = await _services.add({
      'name': name,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> setServiceActive({
    required String serviceId,
    required bool active,
  }) async {
    await _services.doc(serviceId).update({'active': active});
  }
}
