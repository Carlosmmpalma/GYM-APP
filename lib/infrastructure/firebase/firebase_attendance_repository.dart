import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/attendance.dart';
import '../../repositories/attendance_repository.dart';

Attendance _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return Attendance(
    memberId: doc.id,
    status: (data['status'] as String? ?? 'attended') == 'attended'
        ? AttendanceStatus.attended
        : AttendanceStatus.noShow,
    recordedBy: data['recordedBy'] as String? ?? '',
    recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}

class FirebaseAttendanceRepository implements AttendanceRepository {
  FirebaseAttendanceRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> _attendance(String occurrenceId) => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionOccurrences')
      .doc(occurrenceId)
      .collection('attendance');

  @override
  Stream<List<Attendance>> watchAttendanceForOccurrence(String occurrenceId) {
    return _attendance(occurrenceId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<void> recordAttendance({
    required String occurrenceId,
    required String memberId,
    required AttendanceStatus status,
    required String recordedBy,
  }) async {
    await _attendance(occurrenceId).doc(memberId).set({
      'status': status == AttendanceStatus.attended ? 'attended' : 'no_show',
      'recordedBy': recordedBy,
      'recordedAt': FieldValue.serverTimestamp(),
    });
  }
}
