import 'package:equatable/equatable.dart';

enum BookingStatus { booked, cancelled }

/// Domain Model v1 §24 — distingue quem originou a reserva. Na Fase 2
/// só `self` é possível (o próprio membro marca-se); `instructor`/
/// `manager` (atribuição manual) ficam para a Fase 5+/6.
enum BookingSource { self, instructor, manager }

/// Reserva de um membro numa [SessionOccurrence] (Domain Model v1 §23).
///
/// O id do documento é sempre igual ao `memberId` — um membro nunca tem
/// mais do que uma reserva válida por ocorrência (Domain Model v1 §23),
/// e usar o uid como id evita uma query extra só para verificar isso.
class Booking extends Equatable {
  const Booking({
    required this.id,
    required this.occurrenceId,
    required this.memberId,
    required this.status,
    required this.source,
    required this.isExtra,
    required this.createdAt,
    this.cancelledAt,
  });

  final String id;
  final String occurrenceId;
  final String memberId;
  final BookingStatus status;
  final BookingSource source;
  final bool isExtra;
  final DateTime createdAt;
  final DateTime? cancelledAt;

  @override
  List<Object?> get props => [
        id,
        occurrenceId,
        memberId,
        status,
        source,
        isExtra,
        createdAt,
        cancelledAt,
      ];
}

/// UC06/07/08/09 (fechado): "a primeira marcação que o sistema
/// conseguir confirmar ocupa a vaga; qualquer pedido a seguir... recebe
/// simplesmente um erro". Exceção dedicada para que a UI mostre
/// exatamente essa mensagem, distinta de outros erros de booking.
class BookingCapacityExceededException implements Exception {
  const BookingCapacityExceededException();

  @override
  String toString() => 'Já não há vagas — a aula ficou cheia entretanto.';
}

class AlreadyBookedException implements Exception {
  const AlreadyBookedException();

  @override
  String toString() => 'Já tens uma marcação nesta sessão.';
}

class BookingNotFoundException implements Exception {
  const BookingNotFoundException();

  @override
  String toString() => 'Não tens uma marcação ativa nesta sessão.';
}

class SessionNotBookableException implements Exception {
  const SessionNotBookableException();

  @override
  String toString() => 'Esta sessão já não está disponível.';
}
