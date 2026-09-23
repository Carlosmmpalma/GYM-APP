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
    modalityId: data['modalityId'] as String?,
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

  @override
  Future<int> countActiveSeries() async {
    final snapshot =
        await _series.where('status', isEqualTo: 'active').count().get();
    return snapshot.count ?? 0;
  }

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
    String? modalityId,
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
      'modalityId': modalityId,
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
      'modalityId': series.modalityId,
      'dayOfWeek': series.dayOfWeek,
      'startTime': series.startTime,
      'durationMinutes': series.durationMinutes,
      'capacity': series.capacity,
      'startDate': Timestamp.fromDate(series.startDate),
      'preAssignedMemberIds': series.preAssignedMemberIds,
      'status': series.status.name,
    });
  }

  /// Passou de escrita direta para Cloud Function, e por duas razões.
  ///
  /// Era um batch que punha `status: 'cancelled'` na série e em cada
  /// ocorrência futura. As Rules passaram a exigir, no `update` de
  /// `sessionOccurrences`, que `status` não mude por escrita direta —
  /// e como um batch é atómico, o cancelamento inteiro falhava com
  /// `permission-denied`. A um Gestor, que tem todas as permissões.
  ///
  /// A regra está certa: cancelar tem de CASCATAR. Mesmo que passasse,
  /// este código só mudava `status` — as marcações dos alunos ficavam
  /// `booked` numa aula cancelada e a utilização semanal continuava
  /// consumida. O aluno perdia a sessão do plano por causa de uma aula
  /// que o estúdio cancelou.
  ///
  /// `cancelOccurrenceForStudio` foi migrado na altura em que a regra
  /// entrou; este ficou para trás.
  @override
  Future<void> cancelSeries(String seriesId) async {
    await _functions
        .httpsCallable('cancelSeriesForStudio')
        .call<void>({'seriesId': seriesId});
  }

  @override
  Future<void> generateNow() async {
    await _functions
        .httpsCallable('generateRecurringOccurrencesNow')
        .call<void>();
  }
}
