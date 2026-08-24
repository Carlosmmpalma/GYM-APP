import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/waitlist_entry.dart';
import '../../repositories/waitlist_repository.dart';

/// Ver `firebase/functions/src/waitlist.ts` para as regras de quem pode
/// entrar na fila. Aqui só se traduzem os erros de volta para exceções
/// de domínio, mesmo padrão de `firebase_booking_repository.dart`.
class FirebaseWaitlistRepository implements WaitlistRepository {
  FirebaseWaitlistRepository(this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> _entryRef(
    String occurrenceId,
    String memberId,
  ) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(occurrenceId)
          .collection('waitlist')
          .doc(memberId);

  @override
  Future<void> join({
    required String occurrenceId,
    required String memberId,
  }) async {
    try {
      await _functions.httpsCallable('joinWaitlist').call<Object?>({
        'occurrenceId': occurrenceId,
        'memberId': memberId,
      });
    } on FirebaseFunctionsException catch (e) {
      final reason = e.details is Map ? (e.details as Map)['reason'] : null;
      switch (reason) {
        case 'has-capacity':
          throw const WaitlistHasCapacityException();
        case 'already-booked':
          throw const WaitlistAlreadyBookedException();
        case 'not-eligible':
          throw const WaitlistNotEligibleException();
      }
      rethrow;
    }
  }

  @override
  Future<void> leave({
    required String occurrenceId,
    required String memberId,
  }) async {
    await _functions.httpsCallable('leaveWaitlist').call<Object?>({
      'occurrenceId': occurrenceId,
      'memberId': memberId,
    });
  }

  @override
  Stream<List<WaitlistEntry>> watchQueue(String occurrenceId) {
    return _firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(occurrenceId)
        .collection('waitlist')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return WaitlistEntry(
              memberId: doc.id,
              joinedAt:
                  (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              position: (data['position'] as num?)?.toInt(),
            );
          }).toList(),
        );
  }

  @override
  Stream<WaitlistEntry?> watchEntry({
    required String occurrenceId,
    required String memberId,
  }) {
    return _entryRef(occurrenceId, memberId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return WaitlistEntry(
        memberId: memberId,
        joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        position: (data['position'] as num?)?.toInt(),
      );
    });
  }
}
