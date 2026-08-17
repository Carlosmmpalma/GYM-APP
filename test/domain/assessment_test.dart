import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/assessment.dart';

Assessment _assessment({
  double peso = 70,
  double altura = 1.75,
  DateTime? updatedAt,
}) {
  return Assessment(
    id: 'assessment_1',
    memberId: 'member_1',
    instructorId: 'staff_1',
    createdAt: DateTime(2026, 1, 5),
    updatedAt: updatedAt,
    idade: 30,
    peso: peso,
    altura: altura,
    percentMassaGorda: 20,
    massaMuscular: 30,
    gorduraVisceral: 8,
    metabolismoBasal: 1600,
    percentAgua: 55,
    idadeMetabolica: 28,
    pressaoArterial: '112/72',
    perimetroCintura: 80,
    perimetroAbdominal: 85,
    forcaMS: 'Boa',
    forcaMI: 'Boa',
    forcaCore: 'Média',
    flexibilidade: 'Média',
    resistencia: 'Boa',
  );
}

void main() {
  group('imc', () {
    test('calculado a partir de peso/altura, nunca guardado como input', () {
      final assessment = _assessment(peso: 70, altura: 1.75);
      expect(assessment.imc, closeTo(22.86, 0.01));
    });

    test('altura 0 não rebenta — devolve 0', () {
      expect(_assessment(altura: 0).imc, 0);
    });
  });

  group('wasEdited', () {
    test('false quando nunca editada (updatedAt null)', () {
      expect(_assessment().wasEdited, isFalse);
    });

    test('true depois de uma edição (UC04/UC14 fechado)', () {
      expect(_assessment(updatedAt: DateTime(2026, 2, 1)).wasEdited, isTrue);
    });
  });

  group('Equatable', () {
    test('duas avaliações com os mesmos campos são iguais', () {
      expect(_assessment(), equals(_assessment()));
    });

    test('peso diferente torna-as diferentes', () {
      expect(_assessment(peso: 70), isNot(equals(_assessment(peso: 71))));
    });
  });
}
