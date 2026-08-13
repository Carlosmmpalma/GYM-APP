import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/book_session_use_case.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/repositories/booking_repository.dart';

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
  Future<void> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async {}

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) => const Stream.empty();
}

void main() {
  test('delega no repository com os parâmetros corretos', () async {
    final repo = _FakeBookingRepository();
    final useCase = BookSessionUseCase(repo);

    await useCase(occurrenceId: 'occ_1', memberId: 'member_1');

    expect(repo.lastOccurrenceId, 'occ_1');
    expect(repo.lastMemberId, 'member_1');
  });

  test('propaga BookingCapacityExceededException sem a transformar', () async {
    final repo = _FakeBookingRepository()
      ..throwOnCreate = const BookingCapacityExceededException();
    final useCase = BookSessionUseCase(repo);

    expect(
      () => useCase(occurrenceId: 'occ_1', memberId: 'member_1'),
      throwsA(isA<BookingCapacityExceededException>()),
    );
  });
}
