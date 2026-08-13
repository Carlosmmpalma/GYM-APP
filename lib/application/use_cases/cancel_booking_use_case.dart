import '../../repositories/booking_repository.dart';

class CancelBookingUseCase {
  const CancelBookingUseCase(this._repository);

  final BookingRepository _repository;

  /// Devolve se a utilização semanal foi devolvida — ver
  /// `BookingRepository.cancelBooking`.
  Future<bool> call({required String occurrenceId, required String memberId}) {
    return _repository.cancelBooking(
      occurrenceId: occurrenceId,
      memberId: memberId,
    );
  }
}
