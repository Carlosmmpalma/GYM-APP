import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/ping_result.dart';

void main() {
  group('PingResult', () {
    test('duas instâncias com os mesmos valores são iguais (Equatable)', () {
      final now = DateTime(2026, 8, 13, 10, 0);
      final a = PingResult(id: '1', message: 'oi', recordedAt: now);
      final b = PingResult(id: '1', message: 'oi', recordedAt: now);

      expect(a, equals(b));
    });

    test('instâncias com valores diferentes não são iguais', () {
      final now = DateTime(2026, 8, 13, 10, 0);
      final a = PingResult(id: '1', message: 'oi', recordedAt: now);
      final b = PingResult(id: '2', message: 'oi', recordedAt: now);

      expect(a, isNot(equals(b)));
    });
  });
}
