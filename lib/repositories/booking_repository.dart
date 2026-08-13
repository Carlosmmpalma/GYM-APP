import '../domain/entities/booking.dart';

/// Fase 2 — vertical slice de booking.
///
/// createBooking/cancelBooking são implementados como transações
/// Firestore client-side (Platform Foundation §17), não Cloud
/// Functions — ver nota de arquitetura no ficheiro de implementação
/// (`infrastructure/firebase/firebase_booking_repository.dart`).
abstract class BookingRepository {
  /// Lança [SessionNotBookableException], [BookingCapacityExceededException]
  /// ou [AlreadyBookedException] consoante o caso — nunca uma exceção
  /// genérica, para a UI poder mostrar a mensagem certa (UC06/07/08/09).
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  });

  /// Lança [BookingNotFoundException] se não houver marcação ativa.
  Future<void> cancelBooking({
    required String occurrenceId,
    required String memberId,
  });

  /// UC10 — "Minhas marcações". Usa uma collectionGroup query
  /// (`bookings` existe como subcollection de cada ocorrência); mesmo
  /// sem filtrar tenant explicitamente na query, as Security Rules só
  /// deixam ver documentos do próprio tenant, e o `memberId` (== uid)
  /// só existe sob o tenant a que esse uid pertence — não há fuga
  /// possível entre tenants aqui.
  Stream<List<Booking>> watchMyBookings(String memberId);
}
