import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_booking_repository.dart';

const _tenantId = 'tenant_test';
const _occurrenceId = 'occurrence_1';

Future<FakeFirebaseFirestore> _firestoreWithOccurrence({required int capacity}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionOccurrences')
      .doc(_occurrenceId)
      .set({
    'serviceId': 'service_1',
    'startAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10)),
    'endAt': Timestamp.fromDate(DateTime(2026, 1, 1, 11)),
    'capacity': capacity,
    'status': 'scheduled',
    'activeBookingCount': 0,
  });
  return firestore;
}

void main() {
  group('FirebaseBookingRepository.createBooking', () {
    test('cria a marcação e incrementa activeBookingCount quando há vaga',
        () async {
      final firestore = await _firestoreWithOccurrence(capacity: 2);
      final repository = FirebaseBookingRepository(firestore, _tenantId);

      await repository.createBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );

      final occurrenceDoc = await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(_occurrenceId)
          .get();
      expect(occurrenceDoc.data()!['activeBookingCount'], 1);

      final bookingDoc = await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(_occurrenceId)
          .collection('bookings')
          .doc('member_1')
          .get();
      expect(bookingDoc.exists, isTrue);
      expect(bookingDoc.data()!['status'], 'booked');
    });

    test('lança BookingCapacityExceededException quando a ocorrência está cheia',
        () async {
      final firestore = await _firestoreWithOccurrence(capacity: 1);
      final repository = FirebaseBookingRepository(firestore, _tenantId);

      await repository.createBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );

      expect(
        () => repository.createBooking(
          occurrenceId: _occurrenceId,
          memberId: 'member_2',
        ),
        throwsA(isA<BookingCapacityExceededException>()),
      );
    });

    test('lança AlreadyBookedException se o mesmo membro tentar marcar duas vezes',
        () async {
      final firestore = await _firestoreWithOccurrence(capacity: 5);
      final repository = FirebaseBookingRepository(firestore, _tenantId);

      await repository.createBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );

      expect(
        () => repository.createBooking(
          occurrenceId: _occurrenceId,
          memberId: 'member_1',
        ),
        throwsA(isA<AlreadyBookedException>()),
      );
    });
  });

  group('FirebaseBookingRepository.cancelBooking', () {
    test('cancela e decrementa activeBookingCount', () async {
      final firestore = await _firestoreWithOccurrence(capacity: 3);
      final repository = FirebaseBookingRepository(firestore, _tenantId);

      await repository.createBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );
      await repository.cancelBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );

      final occurrenceDoc = await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(_occurrenceId)
          .get();
      expect(occurrenceDoc.data()!['activeBookingCount'], 0);

      final bookingDoc = await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(_occurrenceId)
          .collection('bookings')
          .doc('member_1')
          .get();
      expect(bookingDoc.data()!['status'], 'cancelled');
    });

    test('lança BookingNotFoundException se não houver marcação ativa', () async {
      final firestore = await _firestoreWithOccurrence(capacity: 3);
      final repository = FirebaseBookingRepository(firestore, _tenantId);

      expect(
        () => repository.cancelBooking(
          occurrenceId: _occurrenceId,
          memberId: 'member_sem_marcacao',
        ),
        throwsA(isA<BookingNotFoundException>()),
      );
    });

    test('depois de cancelar, o mesmo membro consegue voltar a marcar', () async {
      final firestore = await _firestoreWithOccurrence(capacity: 1);
      final repository = FirebaseBookingRepository(firestore, _tenantId);

      await repository.createBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );
      await repository.cancelBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );

      await repository.createBooking(
        occurrenceId: _occurrenceId,
        memberId: 'member_1',
      );

      final bookingDoc = await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(_occurrenceId)
          .collection('bookings')
          .doc('member_1')
          .get();
      expect(bookingDoc.data()!['status'], 'booked');
    });
  });
}
