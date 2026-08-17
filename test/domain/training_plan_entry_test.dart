import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/training_plan_entry.dart';

TrainingPlanEntry _entry({double? currentLoad}) {
  return TrainingPlanEntry(
    id: 'entry_1',
    memberId: 'member_1',
    exerciseId: 'exercise_1',
    sets: 4,
    reps: 8,
    currentLoad: currentLoad,
  );
}

void main() {
  test('currentLoad null para exercícios isométricos (ex.: Prancha)', () {
    expect(_entry().currentLoad, isNull);
  });

  group('Equatable', () {
    test('duas entradas com os mesmos campos são iguais', () {
      expect(_entry(currentLoad: 60), equals(_entry(currentLoad: 60)));
    });

    test('currentLoad diferente torna-as diferentes', () {
      expect(_entry(currentLoad: 60), isNot(equals(_entry(currentLoad: 62.5))));
    });
  });
}
