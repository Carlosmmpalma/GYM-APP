import 'package:equatable/equatable.dart';

enum SessionOccurrenceStatus { scheduled, cancelled }

/// Ocorrência concreta de uma atividade reservável (Domain Model v1
/// §21-22, Firestore Data Model v1 §20-28).
///
/// Na Fase 2 as ocorrências são criadas manualmente pelo seed script,
/// sem série/recorrência (isso é Fase 5). `activeBookingCount` é um
/// read model derivado — a fonte de verdade são os documentos de
/// `Booking`; nunca escrever este campo diretamente fora da transação
/// de booking/cancelamento.
class SessionOccurrence extends Equatable {
  const SessionOccurrence({
    required this.id,
    required this.serviceId,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.status,
    required this.activeBookingCount,
  });

  final String id;
  final String serviceId;
  final DateTime startAt;
  final DateTime endAt;
  final int capacity;
  final SessionOccurrenceStatus status;
  final int activeBookingCount;

  int get availableSlots => capacity - activeBookingCount;

  bool get isFull => availableSlots <= 0;

  bool get isBookable => status == SessionOccurrenceStatus.scheduled && !isFull;

  @override
  List<Object?> get props =>
      [id, serviceId, startAt, endAt, capacity, status, activeBookingCount];
}
