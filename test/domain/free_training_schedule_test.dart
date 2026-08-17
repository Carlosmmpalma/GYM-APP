import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/free_training_schedule.dart';

FreeTrainingSchedule _schedule({
  FreeTrainingScheduleStatus status = FreeTrainingScheduleStatus.draft,
}) {
  return FreeTrainingSchedule(
    weekId: '2026-08-17',
    weekStart: DateTime(2026, 8, 17),
    status: status,
  );
}

void main() {
  group('isPublished', () {
    test('status published → true', () {
      expect(
          _schedule(status: FreeTrainingScheduleStatus.published).isPublished,
          isTrue);
    });

    test('status draft/suggested → false', () {
      expect(_schedule(status: FreeTrainingScheduleStatus.draft).isPublished,
          isFalse);
      expect(
          _schedule(status: FreeTrainingScheduleStatus.suggested).isPublished,
          isFalse);
    });
  });

  group('Equatable', () {
    test('duas grelhas com os mesmos campos são iguais', () {
      expect(_schedule(), equals(_schedule()));
    });

    test('status diferente torna-as diferentes', () {
      expect(
        _schedule(status: FreeTrainingScheduleStatus.draft),
        isNot(equals(_schedule(status: FreeTrainingScheduleStatus.suggested))),
      );
    });
  });
}
