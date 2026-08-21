import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/payment_record.dart';

MemberSummary _member({
  DateTime? birthDate,
  String nif = '',
  PaymentStatus? currentPaymentStatus,
  String? currentPaymentPeriod,
}) {
  return MemberSummary(
    uid: 'member_1',
    memberNumber: '000001',
    name: 'Rita Ferreira',
    active: true,
    birthDate: birthDate,
    nif: nif,
    currentPaymentStatus: currentPaymentStatus,
    currentPaymentPeriod: currentPaymentPeriod,
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

  group('currentMonthStatus / isOverdueFor (Fase 9, UC01/UC27 fechados)', () {
    final now = DateTime.utc(2026, 8, 15);
    final thisMonthKey = paymentPeriodKey(now);

    test('sem nenhum registo → currentMonthStatus null, nunca em atraso', () {
      final member = _member();
      expect(member.currentMonthStatus(now), isNull);
      expect(member.isOverdueFor(now), isFalse);
    });

    test(
        'registo de um mês ANTERIOR → currentMonthStatus null (nunca "esquecido em atraso")',
        () {
      final member = _member(
        currentPaymentStatus: PaymentStatus.overdue,
        currentPaymentPeriod: '2026-06',
      );
      expect(member.currentMonthStatus(now), isNull);
      expect(member.isOverdueFor(now), isFalse);
    });

    test('registo do MÊS ATUAL com overdue → bloqueia', () {
      final member = _member(
        currentPaymentStatus: PaymentStatus.overdue,
        currentPaymentPeriod: thisMonthKey,
      );
      expect(member.currentMonthStatus(now), PaymentStatus.overdue);
      expect(member.isOverdueFor(now), isTrue);
    });

    test('registo do MÊS ATUAL com paidLate → NÃO bloqueia', () {
      final member = _member(
        currentPaymentStatus: PaymentStatus.paidLate,
        currentPaymentPeriod: thisMonthKey,
      );
      expect(member.currentMonthStatus(now), PaymentStatus.paidLate);
      expect(member.isOverdueFor(now), isFalse);
    });
  });
}
