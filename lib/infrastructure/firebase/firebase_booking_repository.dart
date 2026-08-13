import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/booking.dart';
import '../../domain/entities/subscription.dart';
import '../../repositories/booking_repository.dart';

Booking _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  // occurrenceId é o segmento pai do path:
  // tenants/{t}/sessionOccurrences/{occurrenceId}/bookings/{bookingId}
  final occurrenceId = doc.reference.parent.parent!.id;
  return Booking(
    id: doc.id,
    occurrenceId: occurrenceId,
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
    // `null` em bookings de seed anteriores à Fase 4 — ver nota em
    // `booking.dart`.
    serviceId: data['serviceId'] as String?,
    period: data['period'] as String?,
  );
}

/// Nota de arquitetura (Fase 4, substitui a nota da Fase 2): createBooking/
/// cancelBooking passaram de transação Firestore client-side para Cloud
/// Functions (Admin SDK) — mesmo motivo que já tinha levado
/// `createSubscription` a ser Cloud Function na Fase 3, agora aplicado
/// aqui também: a partir desta fase, a transação de booking precisa de
/// validar o limite semanal de utilização
/// (`usage/{memberId}_{serviceId}_{period}`), o que Firestore Data
/// Model v1 §52 pede explicitamente que não fique só a cargo do
/// cliente/Security Rules. A lógica completa (elegibilidade, limite
/// semanal, `isExtra`, concorrência na última vaga) vive agora em
/// `firebase/functions/src/createBooking.ts`/`cancelBooking.ts` — este
/// ficheiro só chama essas funções e traduz os erros de volta para as
/// exceções de domínio, mesmo padrão já usado em
/// `firebase_subscription_repository.dart` para `createSubscription`.
///
/// Repara que, ao contrário de todos os outros repositories Firebase
/// deste projeto, este NÃO recebe `tenantId` — apanhado pelo
/// `flutter analyze` (`unused_field`) ao remover a última leitura
/// direta do Firestore sob `tenants/{tenantId}/...`. Nem `createBooking`/
/// `cancelBooking` precisam (o tenant vem dos custom claims do
/// chamador, do lado do servidor — ver `requireAuthenticated` em
/// `callerContext.ts`), nem `watchMyBookings` (a query já era só por
/// `memberId`, mesma nota de isolamento usada em `recalculateUsage.ts`:
/// um uid só pertence a um tenant).
class FirebaseBookingRepository implements BookingRepository {
  FirebaseBookingRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    try {
      await _functions.httpsCallable('createBooking').call<void>({
        'occurrenceId': occurrenceId,
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
      }
      if (e.code == 'not-found') {
        throw const SessionNotBookableException();
      }
      if (e.code == 'permission-denied') {
        throw const NotEligibleForServiceException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    try {
      final result = await _functions.httpsCallable('cancelBooking').call<Object?>({
        'occurrenceId': occurrenceId,
        'memberId': memberId,
      });
      // Defensivo (mesmo padrão de firebase_user_provisioning_repository.dart):
      // `result.data` pode chegar como `Map<Object?, Object?>` no Flutter
      // Web por causa do interop com JS, daí não fazer um `as Map<String,
      // dynamic>` direto.
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
  Stream<List<Booking>> watchMyBookings(String memberId) {
    return _firestore
        .collectionGroup('bookings')
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }
}
