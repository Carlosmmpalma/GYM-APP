import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/book_session_use_case.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/domain/entities/subscription.dart';
import 'package:gym_saas/repositories/booking_repository.dart';
import 'package:gym_saas/repositories/subscription_repository.dart';

class _FakeBookingRepository implements BookingRepository {
  String? lastOccurrenceId;
  String? lastMemberId;
  Exception? throwOnCreate;

  @override
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    lastOccurrenceId = occurrenceId;
    lastMemberId = memberId;
    if (throwOnCreate != null) throw throwOnCreate!;
  }

  @override
  Future<bool> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async =>
      false;

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) =>
      const Stream.empty();

  @override
  Stream<List<Booking>> watchBookingsForOccurrence(String occurrenceId) =>
      const Stream.empty();
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  bool eligible = true;

  @override
  Future<bool> isEligibleForService({
    required String memberId,
    required String serviceId,
  }) async =>
      eligible;

  @override
  Future<void> createSubscription({
    required String memberId,
    required String planId,
    required double agreedPrice,
    required String currency,
  }) async {}

  @override
  Stream<List<Subscription>> watchMemberSubscriptions(String memberId) =>
      const Stream.empty();

  @override
  Future<String?> getGrantingPlanId({
    required String memberId,
    required String serviceId,
  }) async =>
      null;

  @override
  Stream<Set<String>> watchEligibleMemberIds(String serviceId) =>
      const Stream.empty();
}

void main() {
  test(
      'delega no repository de booking com os parâmetros corretos quando elegível',
      () async {
    final bookingRepo = _FakeBookingRepository();
    final subscriptionRepo = _FakeSubscriptionRepository();
    final useCase = BookSessionUseCase(bookingRepo, subscriptionRepo);

    await useCase(
      occurrenceId: 'occ_1',
      serviceId: 'service_1',
      memberId: 'member_1',
    );

    expect(bookingRepo.lastOccurrenceId, 'occ_1');
    expect(bookingRepo.lastMemberId, 'member_1');
  });

  test(
      'lança NotEligibleForServiceException e nunca chega a chamar o booking repository '
      'quando o membro não é elegível', () async {
    final bookingRepo = _FakeBookingRepository();
    final subscriptionRepo = _FakeSubscriptionRepository()..eligible = false;
    final useCase = BookSessionUseCase(bookingRepo, subscriptionRepo);

    await expectLater(
      () => useCase(
        occurrenceId: 'occ_1',
        serviceId: 'service_1',
        memberId: 'member_1',
      ),
      throwsA(isA<NotEligibleForServiceException>()),
    );
    expect(bookingRepo.lastOccurrenceId, isNull);
  });

  test('propaga BookingCapacityExceededException sem a transformar', () async {
    final bookingRepo = _FakeBookingRepository()
      ..throwOnCreate = const BookingCapacityExceededException();
    final subscriptionRepo = _FakeSubscriptionRepository();
    final useCase = BookSessionUseCase(bookingRepo, subscriptionRepo);

    expect(
      () => useCase(
        occurrenceId: 'occ_1',
        serviceId: 'service_1',
        memberId: 'member_1',
      ),
      throwsA(isA<BookingCapacityExceededException>()),
    );
  });
}
