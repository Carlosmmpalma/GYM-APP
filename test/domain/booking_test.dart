import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/booking.dart';

void main() {
  group('TooCloseToStartException', () {
    test('toString() inclui os minutos exigidos (UC06/07/08/09 fechado)', () {
      const exception = TooCloseToStartException(minutesRequired: 30);
      expect(exception.toString(), contains('30'));
    });
  });
}
