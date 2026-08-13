import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/cancel_booking_use_case.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/repositories/booking_repository.dart';

class _FakeBookingRepository implements BookingRepository {
  String? lastOccurrenceId;
  String? lastMemberId;

  @override
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  }) async {}

  @override
  Future<void> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    lastOccurrenceId = occurrenceId;
    lastMemberId = memberId;
  }

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) => const Stream.empty();
}

void main() {
  test('delega no repository com os parâmetros corretos', () async {
    final repo = _FakeBookingRepository();
    final useCase = CancelBookingUseCase(repo);

    await useCase(occurrenceId: 'occ_1', memberId: 'member_1');

    expect(repo.lastOccurrenceId, 'occ_1');
    expect(repo.lastMemberId, 'member_1');
  });
}
