import 'package:equatable/equatable.dart';

/// Fase 7 (Firestore Data Model v1 §40) — um bloco horário reservável
/// dentro de uma [FreeTrainingSchedule]
/// (`tenants/{t}/freeTrainingSchedules/{weekId}/slots/{slotId}`).
/// Mesmo mecanismo de capacidade/booking de um `SessionOccurrence`
/// (Domain Model v1 §30: "este modelo deverá ser tratado
/// separadamente do modelo de SessionTemplate/SessionOccurrence", mas
/// "os bookings utilizam o mesmo conceito geral de booking" — por isso
/// reutiliza `Booking`/`bookingLogic.ts`, só a estrutura do slot em si
/// é nova). `serviceId` denormalizado aqui (não só na semana) pelo
/// mesmo motivo de `SessionOccurrence.serviceId`: o slot guarda os
/// valores efetivos, nunca precisa de consultar o pai para ser
/// interpretado ou reservado.
///
/// Sem `status` — ao contrário de `SessionOccurrence`, esta fase não
/// pede cancelar um bloco isolado (só a semana inteira, via o estado
/// da própria [FreeTrainingSchedule]); `bookingLogic.ts` trata a
/// ausência do campo como "scheduled" por omissão.
class FreeTrainingSlot extends Equatable {
  const FreeTrainingSlot({
    required this.id,
    required this.weekId,
    required this.serviceId,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.activeBookingCount,
  });

  final String id;
  final String weekId;
  final String serviceId;
  final DateTime startAt;
  final DateTime endAt;
  final int capacity;
  final int activeBookingCount;

  int get availableSlots => capacity - activeBookingCount;

  bool get isFull => availableSlots <= 0;

  @override
  List<Object?> get props => [
        id,
        weekId,
        serviceId,
        startAt,
        endAt,
        capacity,
        activeBookingCount,
      ];
}
