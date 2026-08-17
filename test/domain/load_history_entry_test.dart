import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/load_history_entry.dart';

LoadHistoryEntry _entry({double load = 60, DateTime? recordedAt}) {
  return LoadHistoryEntry(
    id: 'entry_1',
    memberId: 'member_1',
    exerciseId: 'exercise_1',
    load: load,
    reps: 8,
    recordedAt: recordedAt ?? DateTime(2026, 8, 9),
    recordedBy: 'staff_1',
  );
}

void main() {
  group('Equatable', () {
    test('dois registos com os mesmos campos são iguais', () {
      expect(_entry(), equals(_entry()));
    });

    test(
        'load diferente torna-os diferentes (UC16: cada alteração é um registo novo)',
        () {
      expect(_entry(load: 60), isNot(equals(_entry(load: 62.5))));
    });

    test('recordedAt diferente torna-os diferentes', () {
      expect(
        _entry(recordedAt: DateTime(2026, 8, 9)),
        isNot(equals(_entry(recordedAt: DateTime(2026, 7, 15)))),
      );
    });
  });
}
