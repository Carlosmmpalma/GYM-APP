import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/free_training_slot.dart';

FreeTrainingSlot _slot({
  int capacity = 10,
  int activeBookingCount = 0,
}) {
  return FreeTrainingSlot(
    id: 'slot_1',
    weekId: '2026-08-17',
    serviceId: 'service_1',
    startAt: DateTime(2026, 8, 17, 6, 0),
    endAt: DateTime(2026, 8, 17, 8, 0),
    capacity: capacity,
    activeBookingCount: activeBookingCount,
  );
}

void main() {
  group('availableSlots / isFull', () {
    test('vagas disponíveis = capacidade - inscritos', () {
      expect(_slot(capacity: 10, activeBookingCount: 4).availableSlots, 6);
    });

    test('cheio quando inscritos == capacidade', () {
      final slot = _slot(capacity: 5, activeBookingCount: 5);
      expect(slot.availableSlots, 0);
      expect(slot.isFull, isTrue);
    });

    test('não cheio quando ainda há vagas', () {
      expect(_slot(capacity: 5, activeBookingCount: 4).isFull, isFalse);
    });
  });

  group('Equatable', () {
    test('dois slots com os mesmos campos são iguais', () {
      expect(
          _slot(activeBookingCount: 2), equals(_slot(activeBookingCount: 2)));
    });

    test('activeBookingCount diferente torna-os diferentes', () {
      expect(
        _slot(activeBookingCount: 1),
        isNot(equals(_slot(activeBookingCount: 2))),
      );
    });
  });
}
