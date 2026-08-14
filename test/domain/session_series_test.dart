import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/session_series.dart';

SessionSeries _series({
  required int capacity,
  SessionSeriesStatus status = SessionSeriesStatus.active,
  List<String> preAssignedMemberIds = const [],
}) {
  return SessionSeries(
    id: 'series_1',
    serviceId: 'service_1',
    dayOfWeek: DateTime.monday,
    startTime: '18:00',
    durationMinutes: 60,
    capacity: capacity,
    startDate: DateTime(2026, 1, 5),
    status: status,
    preAssignedMemberIds: preAssignedMemberIds,
  );
}

void main() {
  group('SessionSeries.capacityLabel (UC19)', () {
    test('capacidade 1 → Individual', () {
      expect(_series(capacity: 1).capacityLabel, 'Individual');
    });

    test('capacidade 2 → Duo', () {
      expect(_series(capacity: 2).capacityLabel, 'Duo');
    });

    test('capacidade 3 → Trio', () {
      expect(_series(capacity: 3).capacityLabel, 'Trio');
    });

    test('capacidade 6 → Grupo (6)', () {
      expect(_series(capacity: 6).capacityLabel, 'Grupo (6)');
    });
  });

  group('SessionSeries.isActive', () {
    test('status active → true', () {
      expect(_series(capacity: 1, status: SessionSeriesStatus.active).isActive,
          isTrue);
    });

    test('status cancelled → false', () {
      expect(
          _series(capacity: 1, status: SessionSeriesStatus.cancelled).isActive,
          isFalse);
    });
  });

  group('SessionSeries.copyWith', () {
    test('só altera status, mantém o resto', () {
      final original =
          _series(capacity: 4, preAssignedMemberIds: const ['member_1']);
      final cancelled =
          original.copyWith(status: SessionSeriesStatus.cancelled);

      expect(cancelled.status, SessionSeriesStatus.cancelled);
      expect(cancelled.capacity, original.capacity);
      expect(cancelled.preAssignedMemberIds, original.preAssignedMemberIds);
      expect(cancelled, isNot(equals(original)));
    });
  });

  group('Equatable', () {
    test('duas séries com os mesmos campos são iguais', () {
      expect(_series(capacity: 2), equals(_series(capacity: 2)));
    });

    test('capacidade diferente torna-as diferentes', () {
      expect(_series(capacity: 2), isNot(equals(_series(capacity: 3))));
    });
  });
}
