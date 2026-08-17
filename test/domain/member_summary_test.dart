import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';

MemberSummary _member({
  DateTime? birthDate,
  String nif = '',
}) {
  return MemberSummary(
    uid: 'member_1',
    memberNumber: '000001',
    name: 'Rita Ferreira',
    active: true,
    birthDate: birthDate,
    nif: nif,
  );
}

void main() {
  test('dados pessoais novos ficam vazios/null por omissão', () {
    const member = MemberSummary(
      uid: 'member_1',
      memberNumber: '000001',
      name: 'Rita Ferreira',
      active: true,
    );
    expect(member.birthDate, isNull);
    expect(member.address, '');
    expect(member.nif, '');
    expect(member.emergencyContact, '');
  });

  group('Equatable', () {
    test('dois membros com os mesmos campos são iguais', () {
      expect(
        _member(birthDate: DateTime(2000, 1, 1), nif: '123456789'),
        equals(_member(birthDate: DateTime(2000, 1, 1), nif: '123456789')),
      );
    });

    test('nif diferente torna-os diferentes', () {
      expect(
        _member(nif: '123456789'),
        isNot(equals(_member(nif: '987654321'))),
      );
    });

    test('birthDate diferente torna-os diferentes', () {
      expect(
        _member(birthDate: DateTime(2000, 1, 1)),
        isNot(equals(_member(birthDate: DateTime(1999, 1, 1)))),
      );
    });
  });
}
