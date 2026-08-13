import '../../domain/entities/subscription.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/subscription_repository.dart';

/// UC06/07/08/09 — a partir da Fase 3, marcar uma sessão exige um plano
/// ativo que dê acesso ao serviço dessa sessão. A verificação corre
/// ANTES da transação de booking (Fase 2), não dentro dela — não é uma
/// questão de concorrência (dois membros não "competem" pela mesma
/// elegibilidade), por isso não há vantagem em pagar o custo de a
/// meter dentro do `runTransaction`.
class BookSessionUseCase {
  const BookSessionUseCase(this._bookingRepository, this._subscriptionRepository);

  final BookingRepository _bookingRepository;
  final SubscriptionRepository _subscriptionRepository;

  Future<void> call({
    required String occurrenceId,
    required String serviceId,
    required String memberId,
  }) async {
    final eligible = await _subscriptionRepository.isEligibleForService(
      memberId: memberId,
      serviceId: serviceId,
    );
    if (!eligible) {
      throw const NotEligibleForServiceException();
    }

    return _bookingRepository.createBooking(
      occurrenceId: occurrenceId,
      memberId: memberId,
    );
  }
}
