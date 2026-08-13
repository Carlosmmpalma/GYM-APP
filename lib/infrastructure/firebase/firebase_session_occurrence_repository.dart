import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/session_occurrence.dart';
import '../../repositories/session_occurrence_repository.dart';

SessionOccurrence _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return SessionOccurrence(
    id: doc.id,
    serviceId: data['serviceId'] as String,
    startAt: (data['startAt'] as Timestamp).toDate(),
    endAt: (data['endAt'] as Timestamp).toDate(),
    capacity: (data['capacity'] as num).toInt(),
    status: (data['status'] as String? ?? 'scheduled') == 'scheduled'
        ? SessionOccurrenceStatus.scheduled
        : SessionOccurrenceStatus.cancelled,
    activeBookingCount: (data['activeBookingCount'] as num? ?? 0).toInt(),
  );
}

class FirebaseSessionOccurrenceRepository implements SessionOccurrenceRepository {
  FirebaseSessionOccurrenceRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _occurrences => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionOccurrences');

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrences(String serviceId) {
    final now = Timestamp.now();
    return _occurrences
        .where('serviceId', isEqualTo: serviceId)
        .where('startAt', isGreaterThanOrEqualTo: now)
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<SessionOccurrence?> getOccurrence(String occurrenceId) async {
    final snapshot = await _occurrences.doc(occurrenceId).get();
    if (!snapshot.exists) return null;
    return _fromDoc(snapshot);
  }
}
