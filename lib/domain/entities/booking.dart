import 'package:equatable/equatable.dart';

enum BookingStatus { booked, cancelled }

/// Domain Model v1 §24 — distingue quem originou a reserva. Na Fase 2
/// só `self` é possível (o próprio membro marca-se); `instructor`/
/// `manager` (atribuição manual) ficam para a Fase 5+/6.
/// Fase 11 — `waitlist`: a marcação foi feita automaticamente quando
/// vagou um lugar e o membro era o primeiro da lista de espera. Fica
/// distinta das outras porque não partiu de um ato dele naquele momento.
enum BookingSource { self, instructor, manager, waitlist }

/// Onde vive a sessão que esta marcação reservou.
///
/// As duas coisas são marcações a sério, feitas pela mesma transação
/// (`bookingLogic.ts`), mas vivem em caminhos diferentes: uma aula em
/// `sessionOccurrences/{id}/bookings`, o treino livre em
/// `freeTrainingSchedules/{weekId}/slots/{slotId}/bookings`.
///
/// A distinção não é cosmética — cancelar cada uma chama uma Cloud
/// Function diferente. "As minhas marcações" lê as duas com uma
/// collection group query e, sem saber qual era qual, oferecia
/// "Cancelar" nas de treino livre chamando a função das aulas: falhava
/// sempre, e o cartão ficava lá para sempre.
enum BookingKind { session, freeTraining }

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
    this.serviceId,
    this.period,
    this.startAt,
    this.kind = BookingKind.session,
    this.weekId,
  });

  final String id;
  final String occurrenceId;
  final String memberId;
  final BookingStatus status;
  final BookingSource source;
  final bool isExtra;
  final DateTime createdAt;
  final DateTime? cancelledAt;

  /// Fase 4 — denormalizado de `SessionOccurrence.serviceId` no momento
  /// da marcação, para `recalculateUsage` (Cloud Function) não precisar
  /// de um join extra por booking. `null` só em bookings anteriores à
  /// Fase 4 (dados de seed antigos no emulador) — nunca em bookings
  /// novos.
  final String? serviceId;

  /// Fase 4 — chave ISO-8601 week (`YYYY-Www`) da semana do
  /// `SessionOccurrence.startAt` no momento da marcação (não da data em
  /// que foi feita a marcação — o limite é sobre a semana da SESSÃO).
  /// `null` pela mesma razão que [serviceId].
  final String? period;

  /// Quando a sessão reservada começa, copiado no momento da marcação.
  ///
  /// É o que permite ordenar as marcações pela data da SESSÃO (e não
  /// pela data em que foram feitas), esconder as que já passaram, e
  /// saber qual é a próxima sem ir ler uma ocorrência por marcação.
  /// `null` em marcações anteriores a este campo existir — a UI
  /// recorre então à ocorrência, como fazia antes.
  final DateTime? startAt;

  final BookingKind kind;

  /// Só para [BookingKind.freeTraining]: a semana a que o slot
  /// pertence, necessária para o cancelar.
  final String? weekId;

  /// Uma marcação de uma sessão que já começou. Continua a ser um
  /// registo válido — só não há nada a fazer com ela.
  bool hasPassed(DateTime now) => startAt != null && startAt!.isBefore(now);

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
        serviceId,
        period,
        startAt,
        kind,
        weekId,
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

/// Fase 4 — "limite semanal (Standard 1x / Plus 2x / Premium 3x)
/// validado corretamente". Lançada pela Cloud Function `createBooking`
/// quando o membro já esgotou o [limit] de utilizações do serviço no
/// período atual; distinta de [BookingCapacityExceededException]
/// (que é sobre a sessão estar cheia, não sobre o limite do próprio
/// membro).
class UsageLimitReachedException implements Exception {
  const UsageLimitReachedException({required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  String toString() =>
      'Já atingiste o limite semanal deste serviço ($used/$limit).';
}

/// Fase 8 (auditoria funcional, UC06/UC07/UC08/UC09 fechado) —
/// "antecedência mínima para marcar, configurável pelo Gestor"
/// (`tenants/{t}/config/bookingPolicy.minBookingNoticeMinutes`).
/// Lançada só pelo caminho self-service (`createBooking`/
/// `bookFreeTrainingSlot`) — atribuição manual por Instrutor/Gestor
/// nunca passa por esta validação.
class TooCloseToStartException implements Exception {
  const TooCloseToStartException({required this.minutesRequired});

  final int minutesRequired;

  @override
  String toString() =>
      'É preciso marcar com pelo menos $minutesRequired minuto(s) de antecedência.';
}
