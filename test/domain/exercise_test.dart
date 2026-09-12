import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/exercise.dart';

void main() {
  group('hasVideo', () {
    test('true quando videoPath está definido', () {
      const exercise = Exercise(
        id: 'ex_1',
        name: 'Agachamento com barra',
        description: '',
        category: 'Pernas',
        videoPath: 'tenants/t1/exercises/ex_1/video',
      );
      expect(exercise.hasVideo, isTrue);
    });

    test('false quando videoPath é null ("Sem vídeo" no mockup)', () {
      const exercise = Exercise(
        id: 'ex_1',
        name: 'Kettlebell Swing',
        description: '',
        category: 'Full body',
      );
      expect(exercise.hasVideo, isFalse);
    });
  });

  group('Equatable', () {
    test('dois exercícios com os mesmos campos são iguais', () {
      const a = Exercise(
        id: 'ex_1',
        name: 'Sled Push',
        description: 'Empurrar o trenó',
        category: 'Hyrox',
      );
      const b = Exercise(
        id: 'ex_1',
        name: 'Sled Push',
        description: 'Empurrar o trenó',
        category: 'Hyrox',
      );
      expect(a, equals(b));
    });

    test('videoPath diferente torna-os diferentes', () {
      const a = Exercise(
          id: 'ex_1', name: 'Sled Push', description: '', category: 'Hyrox');
      const b = Exercise(
        id: 'ex_1',
        name: 'Sled Push',
        description: '',
        category: 'Hyrox',
        videoPath: 'tenants/t1/exercises/ex_1/video',
      );
      expect(a, isNot(equals(b)));
    });
  });
}
