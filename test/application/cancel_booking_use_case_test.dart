import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/cancel_booking_use_case.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/repositories/booking_repository.dart';

class _FakeBookingRepository implements BookingRepository {
  String? lastOccurrenceId;
  String? lastMemberId;
  bool usageRefundedToReturn = true;

  @override
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  }) async {}

  @override
  Future<bool> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    lastOccurrenceId = occurrenceId;
    lastMemberId = memberId;
    return usageRefundedToReturn;
  }

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) =>
      const Stream.empty();

  @override
  Stream<List<Booking>> watchBookingsForOccurrence(String occurrenceId) =>
      const Stream.empty();
}

void main() {
  test('delega no repository com os parâmetros corretos', () async {
    final repo = _FakeBookingRepository();
    final useCase = CancelBookingUseCase(repo);

    await useCase(occurrenceId: 'occ_1', memberId: 'member_1');

    expect(repo.lastOccurrenceId, 'occ_1');
    expect(repo.lastMemberId, 'member_1');
  });

  // Fase 4 — cancelBooking passou a devolver se a utilização foi
  // devolvida (ver nota em booking_repository.dart); confirma que o
  // use case propaga esse valor tal e qual, sem o esconder.
  test('propaga o valor de usageRefunded devolvido pelo repository', () async {
    final repo = _FakeBookingRepository()..usageRefundedToReturn = false;
    final useCase = CancelBookingUseCase(repo);

    final usageRefunded =
        await useCase(occurrenceId: 'occ_1', memberId: 'member_1');

    expect(usageRefunded, isFalse);
  });
}
