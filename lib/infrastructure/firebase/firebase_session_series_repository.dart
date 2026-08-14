import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/session_series.dart';
import '../../repositories/session_series_repository.dart';

SessionSeries _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return SessionSeries(
    id: doc.id,
    serviceId: data['serviceId'] as String,
    instructorId: data['instructorId'] as String?,
    dayOfWeek: (data['dayOfWeek'] as num).toInt(),
    startTime: data['startTime'] as String,
    durationMinutes: (data['durationMinutes'] as num).toInt(),
    capacity: (data['capacity'] as num).toInt(),
    startDate: (data['startDate'] as Timestamp).toDate(),
    preAssignedMemberIds: ((data['preAssignedMemberIds'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    status: (data['status'] as String? ?? 'active') == 'active'
        ? SessionSeriesStatus.active
        : SessionSeriesStatus.cancelled,
  );
}

class FirebaseSessionSeriesRepository implements SessionSeriesRepository {
  FirebaseSessionSeriesRepository(
      this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _series => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionSeries');

  CollectionReference<Map<String, dynamic>> get _occurrences => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionOccurrences');

  @override
  Stream<List<SessionSeries>> watchSeries() {
    return _series
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<String> createSeries({
    required String serviceId,
    String? instructorId,
    required int dayOfWeek,
    required String startTime,
    required int durationMinutes,
    required int capacity,
    required DateTime startDate,
    List<String> preAssignedMemberIds = const [],
  }) async {
    final ref = await _series.add({
      'serviceId': serviceId,
      'instructorId': instructorId,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'durationMinutes': durationMinutes,
      'capacity': capacity,
      'startDate': Timestamp.fromDate(startDate),
      'preAssignedMemberIds': preAssignedMemberIds,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updateSeries(SessionSeries series) async {
    await _series.doc(series.id).update({
      'serviceId': series.serviceId,
      'instructorId': series.instructorId,
      'dayOfWeek': series.dayOfWeek,
      'startTime': series.startTime,
      'durationMinutes': series.durationMinutes,
      'capacity': series.capacity,
      'startDate': Timestamp.fromDate(series.startDate),
      'preAssignedMemberIds': series.preAssignedMemberIds,
      'status': series.status.name,
    });
  }

  @override
  Future<void> cancelSeries(String seriesId) async {
    final batch = _firestore.batch();
    batch.update(_series.doc(seriesId), {'status': 'cancelled'});

    final futureOccurrences = await _occurrences
        .where('seriesId', isEqualTo: seriesId)
        .where('startAt', isGreaterThan: Timestamp.now())
        .get();
    for (final doc in futureOccurrences.docs) {
      batch.update(doc.reference, {'status': 'cancelled'});
    }
    await batch.commit();
  }

  @override
  Future<void> generateNow() async {
    await _functions
        .httpsCallable('generateRecurringOccurrencesNow')
        .call<void>();
  }
}
