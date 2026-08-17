import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/staff_summary.dart';

StaffSummary _staff({
  String phone = '',
  DateTime? birthDate,
}) {
  return StaffSummary(
    uid: 'staff_1',
    name: 'João Martins',
    email: 'joao@example.com',
    roles: const {Role.instructor},
    active: true,
    phone: phone,
    birthDate: birthDate,
  );
}

void main() {
  test('dados pessoais novos ficam vazios/null por omissão', () {
    const staff = StaffSummary(
      uid: 'staff_1',
      name: 'João Martins',
      email: 'joao@example.com',
      roles: {Role.instructor},
      active: true,
    );
    expect(staff.phone, '');
    expect(staff.birthDate, isNull);
    expect(staff.address, '');
    expect(staff.nif, '');
    expect(staff.emergencyContact, '');
  });

  group('Equatable', () {
    test('dois staff com os mesmos campos são iguais', () {
      expect(
        _staff(phone: '912345678', birthDate: DateTime(1990, 5, 1)),
        equals(_staff(phone: '912345678', birthDate: DateTime(1990, 5, 1))),
      );
    });

    test('phone diferente torna-os diferentes', () {
      expect(
        _staff(phone: '912345678'),
        isNot(equals(_staff(phone: '911111111'))),
      );
    });
  });
}
