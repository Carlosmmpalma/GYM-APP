import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/modality.dart';
import '../../repositories/modality_repository.dart';

Modality _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? const {};
  return Modality(
    id: doc.id,
    name: data['name'] as String? ?? '',
    active: data['active'] as bool? ?? false,
    serviceIds: ((data['serviceIds'] as List?) ?? const [])
        .map((e) => e as String)
        .toSet(),
  );
}

class FirebaseModalityRepository implements ModalityRepository {
  FirebaseModalityRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _modalities =>
      _firestore.collection('tenants').doc(_tenantId).collection('modalities');

  @override
  Stream<List<Modality>> watchModalities() {
    return _modalities.snapshots().map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList(),
        );
  }

  @override
  Future<String> createModality({required String name}) async {
    final ref = await _modalities.add({
      'name': name,
      'active': true,
      'serviceIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> setModalityActive({
    required String modalityId,
    required bool active,
  }) async {
    await _modalities.doc(modalityId).update({'active': active});
  }

  @override
  Future<void> setServiceEnabled({
    required String modalityId,
    required String serviceId,
    required bool enabled,
  }) async {
    await _modalities.doc(modalityId).update({
      'serviceIds': enabled
          ? FieldValue.arrayUnion([serviceId])
          : FieldValue.arrayRemove([serviceId]),
    });
  }
}
