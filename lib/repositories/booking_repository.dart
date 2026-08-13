import '../domain/entities/booking.dart';

/// Fase 2 — vertical slice de booking.
///
/// Até à Fase 3, createBooking/cancelBooking eram transações Firestore
/// client-side (Platform Foundation §17). A partir da Fase 4 passaram
/// a Cloud Functions (Admin SDK) — ver nota de arquitetura em
/// `infrastructure/firebase/firebase_booking_repository.dart` e em
/// `firebase/functions/src/createBooking.ts` sobre porque (limite
/// semanal de utilização, mesmo motivo que já tinha levado
/// `createSubscription` a ser Cloud Function na Fase 3).
abstract class BookingRepository {
  /// Lança [SessionNotBookableException], [BookingCapacityExceededException],
  /// [AlreadyBookedException], [NotEligibleForServiceException] ou
  /// [UsageLimitReachedException] consoante o caso — nunca uma exceção
  /// genérica, para a UI poder mostrar a mensagem certa (UC06/07/08/09,
  /// Fase 4).
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  });

  /// Lança [BookingNotFoundException] se não houver marcação ativa.
  ///
  /// Devolve `true` se a utilização semanal consumida por esta marcação
  /// foi devolvida (dentro da janela de antecedência mínima — ver
  /// `cancelBooking.ts`), `false` caso contrário (fora da janela, ou o
  /// serviço nem sequer tinha limite/usage a devolver). Pedido pelo
  /// Carlos: sem isto, cancelar não dizia ao membro o que realmente
  /// aconteceu à utilização.
  Future<bool> cancelBooking({
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
