import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/attendance.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/free_training_schedule.dart';
import '../../domain/entities/free_training_slot.dart';
import '../../domain/entities/subscription.dart';
import '../../repositories/free_training_repository.dart';

FreeTrainingSchedule _scheduleFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return FreeTrainingSchedule(
    weekId: doc.id,
    weekStart: (data['weekStart'] as Timestamp).toDate(),
    status: FreeTrainingScheduleStatus.values.firstWhere(
      (s) => s.name == (data['status'] as String? ?? 'draft'),
      orElse: () => FreeTrainingScheduleStatus.draft,
    ),
    createdBy: data['createdBy'] as String?,
    publishedAt: (data['publishedAt'] as Timestamp?)?.toDate(),
  );
}

FreeTrainingSlot _slotFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return FreeTrainingSlot(
    id: doc.id,
    // Igual ao truque em `firebase_booking_repository.dart` — o pai é
    // sempre `freeTrainingSchedules/{weekId}`.
    weekId: doc.reference.parent.parent!.id,
    serviceId: data['serviceId'] as String,
    startAt: (data['startAt'] as Timestamp).toDate(),
    endAt: (data['endAt'] as Timestamp).toDate(),
    capacity: (data['capacity'] as num).toInt(),
    activeBookingCount: (data['activeBookingCount'] as num? ?? 0).toInt(),
  );
}

Booking _bookingFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return Booking(
    id: doc.id,
    occurrenceId: doc.reference.parent.parent!.id,
    memberId: data['memberId'] as String,
    status: (data['status'] as String) == 'booked'
        ? BookingStatus.booked
        : BookingStatus.cancelled,
    source: BookingSource.values.firstWhere(
      (s) => s.name == (data['source'] as String? ?? 'self'),
      orElse: () => BookingSource.self,
    ),
    isExtra: data['isExtra'] as bool? ?? false,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
    serviceId: data['serviceId'] as String?,
    period: data['period'] as String?,
  );
}

Attendance _attendanceFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
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

class FirebaseFreeTrainingRepository implements FreeTrainingRepository {
  FirebaseFreeTrainingRepository(
      this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _schedules => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('freeTrainingSchedules');

  DocumentReference<Map<String, dynamic>> _slotDoc(
          String weekId, String slotId) =>
      _schedules.doc(weekId).collection('slots').doc(slotId);

  @override
  Stream<FreeTrainingSchedule?> watchSchedule(String weekId) {
    return _schedules
        .doc(weekId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? _scheduleFromDoc(snapshot) : null);
  }

  @override
  Stream<List<FreeTrainingSlot>> watchSlots(String weekId) {
    return _schedules
        .doc(weekId)
        .collection('slots')
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_slotFromDoc).toList());
  }

  @override
  Stream<List<Booking>> watchSlotBookings(String weekId, String slotId) {
    return _slotDoc(weekId, slotId)
        .collection('bookings')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_bookingFromDoc).toList());
  }

  @override
  Future<Booking?> getMyBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async {
    final snap = await _slotDoc(weekId, slotId)
        .collection('bookings')
        .doc(memberId)
        .get();
    return snap.exists ? _bookingFromDoc(snap) : null;
  }

  @override
  Stream<List<Attendance>> watchSlotAttendance(String weekId, String slotId) {
    return _slotDoc(weekId, slotId)
        .collection('attendance')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_attendanceFromDoc).toList());
  }

  @override
  Future<({String weekId, String status, bool created, int slotsCopied})>
      suggestSchedule({
    required DateTime weekStart,
    required String serviceId,
  }) async {
    final result = await _functions
        .httpsCallable('suggestFreeTrainingSchedule')
        .call<Object?>({
      'weekStart': weekStart.toIso8601String(),
      'serviceId': serviceId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      weekId: data['weekId'] as String,
      status: data['status'] as String,
      created: data['created'] as bool? ?? false,
      slotsCopied: (data['slotsCopied'] as num? ?? 0).toInt(),
    );
  }

  @override
  Future<void> publishSchedule(String weekId) async {
    await _functions.httpsCallable('publishFreeTrainingSchedule').call<void>({
      'weekId': weekId,
    });
  }

  @override
  Future<String> createSlot({
    required String weekId,
    required String serviceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) async {
    final ref = await _schedules.doc(weekId).collection('slots').add({
      'serviceId': serviceId,
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'capacity': capacity,
      'activeBookingCount': 0,
    });
    return ref.id;
  }

  @override
  Future<void> updateSlot({
    required String weekId,
    required String slotId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) async {
    await _slotDoc(weekId, slotId).update({
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'capacity': capacity,
    });
  }

  @override
  Future<void> deleteSlot({
    required String weekId,
    required String slotId,
  }) async {
    await _slotDoc(weekId, slotId).delete();
  }

  @override
  Future<void> bookSlot({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async {
    try {
      await _functions.httpsCallable('bookFreeTrainingSlot').call<void>({
        'weekId': weekId,
        'slotId': slotId,
        'memberId': memberId,
      });
    } on FirebaseFunctionsException catch (e) {
      final reason = e.details is Map ? (e.details as Map)['reason'] : null;
      switch (reason) {
        case 'capacity':
          throw const BookingCapacityExceededException();
        case 'already-booked':
          throw const AlreadyBookedException();
        case 'usage-limit':
          final details = e.details as Map;
          throw UsageLimitReachedException(
            used: (details['used'] as num).toInt(),
            limit: (details['limit'] as num).toInt(),
          );
        case 'too-close-to-start':
          final details = e.details as Map;
          throw TooCloseToStartException(
            minutesRequired: (details['minutesRequired'] as num).toInt(),
          );
      }
      if (e.code == 'not-found' || e.code == 'failed-precondition') {
        throw const SessionNotBookableException();
      }
      if (e.code == 'permission-denied') {
        throw const NotEligibleForServiceException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> cancelSlotBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('cancelFreeTrainingBooking')
          .call<Object?>({
        'weekId': weekId,
        'slotId': slotId,
        'memberId': memberId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['usageRefunded'] as bool? ?? false;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw const BookingNotFoundException();
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, bool>> assignMembers({
    required String weekId,
    required String slotId,
    required List<String> memberIds,
  }) async {
    final result = await _functions
        .httpsCallable('assignMembersToFreeTrainingSlot')
        .call<Object?>({
      'weekId': weekId,
      'slotId': slotId,
      'memberIds': memberIds,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final entries = (data['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map));
    return {
      for (final entry in entries)
        entry['memberId'] as String: entry['ok'] as bool,
    };
  }

  @override
  Future<void> recordAttendance({
    required String weekId,
    required String slotId,
    required String memberId,
    required AttendanceStatus status,
    required String recordedBy,
  }) async {
    await _slotDoc(weekId, slotId).collection('attendance').doc(memberId).set({
      'status': status == AttendanceStatus.attended ? 'attended' : 'no_show',
      'recordedBy': recordedBy,
      'recordedAt': FieldValue.serverTimestamp(),
    });
  }
}
