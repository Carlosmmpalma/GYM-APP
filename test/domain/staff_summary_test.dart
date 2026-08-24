import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/staff_private_profile.dart';
import 'package:gym_saas/domain/entities/staff_summary.dart';

StaffSummary _staff({String name = 'João Martins'}) {
  return StaffSummary(
    uid: 'staff_1',
    name: name,
    email: 'joao@example.com',
    roles: const {Role.instructor},
    active: true,
  );
}

void main() {
  // Última ronda — os dados pessoais do staff saíram deste documento.
  //
  // O documento de staff é legível por todo o tenant (é dele que sai o
  // nome do instrutor no cartão de uma aula); com a morada e o NIF lá
  // dentro, qualquer aluno os conseguia ler. Passaram para
  // `staff/{uid}/private/profile` — ver [StaffPrivateProfile].
  test('o resumo público não carrega dados pessoais', () {
    const staff = StaffSummary(
      uid: 'staff_1',
      name: 'João Martins',
      email: 'joao@example.com',
      roles: {Role.instructor},
      active: true,
    );

    // O que fica é o mínimo para a app funcionar.
    expect(staff.name, 'João Martins');
    expect(staff.roles, {Role.instructor});
    expect(staff.serviceIds, isEmpty);
    expect(staff.modalityIds, isEmpty);
  });

  test('o perfil privado nasce vazio', () {
    const profile = StaffPrivateProfile.empty;
    expect(profile.phone, '');
    expect(profile.birthDate, isNull);
    expect(profile.address, '');
    expect(profile.nif, '');
    expect(profile.emergencyContact, '');
  });

  group('Equatable', () {
    test('dois staff com os mesmos campos são iguais', () {
      expect(_staff(), equals(_staff()));
    });

    test('nome diferente torna-os diferentes', () {
      expect(_staff(), isNot(equals(_staff(name: 'Ana Costa'))));
    });

    test('dois perfis privados com os mesmos campos são iguais', () {
      final profile = StaffPrivateProfile(
        phone: '912345678',
        birthDate: DateTime(1990, 5, 1),
        nif: '123456789',
      );
      expect(
        profile,
        equals(StaffPrivateProfile(
          phone: '912345678',
          birthDate: DateTime(1990, 5, 1),
          nif: '123456789',
        )),
      );
      expect(profile, isNot(equals(StaffPrivateProfile.empty)));
    });
  });
}
