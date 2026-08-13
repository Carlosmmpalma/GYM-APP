import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/role.dart';

void main() {
  test('fromClaim reconhece os três papéis válidos', () {
    expect(Role.fromClaim('member'), Role.member);
    expect(Role.fromClaim('instructor'), Role.instructor);
    expect(Role.fromClaim('manager'), Role.manager);
  });

  test('fromClaim rejeita valores desconhecidos (claim corrompido/malicioso)',
      () {
    expect(() => Role.fromClaim('admin'), throwsArgumentError);
  });
}
