import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
    seriesId: data['seriesId'] as String?,
    instructorId: data['instructorId'] as String?,
  );
}

class FirebaseSessionOccurrenceRepository
    implements SessionOccurrenceRepository {
  FirebaseSessionOccurrenceRepository(
      this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
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
  Stream<List<SessionOccurrence>> watchUpcomingOccurrencesAllServices() {
    final now = Timestamp.now();
    return _occurrences
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

  @override
  Future<String> createOccurrence({
    required String serviceId,
    String? instructorId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) async {
    final ref = await _occurrences.add({
      'serviceId': serviceId,
      'instructorId': instructorId,
      'seriesId': null,
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'capacity': capacity,
      'status': 'scheduled',
      'activeBookingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updateOccurrence({
    required String occurrenceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
    String? instructorId,
  }) async {
    await _occurrences.doc(occurrenceId).update({
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'capacity': capacity,
      'instructorId': instructorId,
    });
  }

  @override
  Future<void> cancelOccurrence(String occurrenceId) async {
    await _occurrences.doc(occurrenceId).update({'status': 'cancelled'});
  }

  @override
  Stream<List<SessionOccurrence>> watchOccurrencesForSeries(String seriesId) {
    return _occurrences
        .where('seriesId', isEqualTo: seriesId)
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Stream<List<SessionOccurrence>> watchOccurrencesStartingBetween(
    DateTime from,
    DateTime to,
  ) {
    return _occurrences
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('startAt', isLessThan: Timestamp.fromDate(to))
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<Map<String, bool>> assignMembers({
    required String occurrenceId,
    required List<String> memberIds,
  }) async {
    final result = await _functions
        .httpsCallable('assignMembersToOccurrence')
        .call<Object?>({
      'occurrenceId': occurrenceId,
      'memberIds': memberIds,
    });
    // Mesmo padrão defensivo de `firebase_usage_repository.dart#recalculateUsage`
    // — o interop do Flutter Web pode devolver `Map<Object?, Object?>`.
    final data = Map<String, dynamic>.from(result.data as Map);
    final entries = (data['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map));
    return {
      for (final entry in entries)
        entry['memberId'] as String: entry['ok'] as bool,
    };
  }
}
