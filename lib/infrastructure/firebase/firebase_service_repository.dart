import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/service.dart';
import '../../repositories/service_repository.dart';

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
    return snapshot.docs
        .map((doc) => Service(
              id: doc.id,
              name: doc.data()['name'] as String? ?? '',
              active: doc.data()['active'] as bool? ?? false,
            ))
        .toList();
  }
}
