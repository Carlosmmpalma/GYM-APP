import '../../repositories/booking_repository.dart';

class BookSessionUseCase {
  const BookSessionUseCase(this._repository);

  final BookingRepository _repository;

  Future<void> call({required String occurrenceId, required String memberId}) {
    return _repository.createBooking(
      occurrenceId: occurrenceId,
      memberId: memberId,
    );
  }
}
