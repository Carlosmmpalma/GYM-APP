import 'package:equatable/equatable.dart';

enum SessionOccurrenceStatus { scheduled, cancelled }

/// Ocorrência concreta de uma atividade reservável (Domain Model v1
/// §21-22, Firestore Data Model v1 §20-28).
///
/// Até à Fase 4 as ocorrências eram sempre criadas manualmente (seed
/// script). Na Fase 5, uma ocorrência pode também ser materializada a
/// partir de uma `SessionSeries` (`seriesId` não nulo) pela Cloud
/// Function `generateRecurringOccurrences` — mas guarda sempre os seus
/// próprios valores efetivos (`startAt`/`endAt`/`capacity`/
/// `instructorId`), nunca precisa de consultar a série para ser
/// interpretada (Firestore Data Model v1 §22: "a ocorrência deve
/// guardar os valores efetivos"). Isto é o que permite editar uma
/// ocorrência isolada ("só esta semana") sem tocar na série.
/// `activeBookingCount` é um read model derivado — a fonte de verdade
/// são os documentos de `Booking`; nunca escrever este campo
/// diretamente fora da transação de booking/cancelamento.
class SessionOccurrence extends Equatable {
  const SessionOccurrence({
    required this.id,
    required this.serviceId,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.status,
    required this.activeBookingCount,
    this.seriesId,
    this.instructorId,
  });

  final String id;
  final String serviceId;
  final DateTime startAt;
  final DateTime endAt;
  final int capacity;
  final SessionOccurrenceStatus status;
  final int activeBookingCount;

  /// Fase 5 — `null` numa ocorrência "só esta data" (ad-hoc) ou numa
  /// ocorrência anterior a esta fase; não-nulo quando materializada a
  /// partir de uma `SessionSeries`.
  final String? seriesId;

  /// Fase 5 — copiado da série no momento da geração, mas editável por
  /// ocorrência sem afetar a série (mesmo raciocínio de `capacity`).
  final String? instructorId;

  int get availableSlots => capacity - activeBookingCount;

  bool get isFull => availableSlots <= 0;

  bool get isBookable => status == SessionOccurrenceStatus.scheduled && !isFull;

  @override
  List<Object?> get props => [
        id,
        serviceId,
        startAt,
        endAt,
        capacity,
        status,
        activeBookingCount,
        seriesId,
        instructorId,
      ];
}
