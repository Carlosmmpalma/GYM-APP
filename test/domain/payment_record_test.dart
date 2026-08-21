import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/payment_record.dart';

void main() {
  group('PaymentStatus.fromValue', () {
    test('reconhece os três valores', () {
      expect(PaymentStatus.fromValue('paid'), PaymentStatus.paid);
      expect(PaymentStatus.fromValue('overdue'), PaymentStatus.overdue);
      expect(PaymentStatus.fromValue('paidLate'), PaymentStatus.paidLate);
    });

    test('valor desconhecido cai para overdue (nunca finge que está pago)', () {
      expect(PaymentStatus.fromValue('lixo'), PaymentStatus.overdue);
    });
  });

  group('paymentPeriodKey', () {
    test('formata YYYY-MM com zero-padding', () {
      expect(paymentPeriodKey(DateTime.utc(2026, 3, 15)), '2026-03');
      expect(paymentPeriodKey(DateTime.utc(2026, 12, 1)), '2026-12');
    });
  });

  group('paymentMonthLabel', () {
    test('"Agosto 2026"', () {
      expect(paymentMonthLabel(8, 2026), 'Agosto 2026');
    });

    test('mês 1 (Janeiro) não fica fora dos limites', () {
      expect(paymentMonthLabel(1, 2026), 'Janeiro 2026');
    });
  });

  group('PaymentRecord', () {
    PaymentRecord record({
      required int year,
      required int month,
      required PaymentStatus status,
    }) =>
        PaymentRecord(
          memberId: 'member_1',
          year: year,
          month: month,
          status: status,
          changedAt: DateTime.utc(2026, 8, 1),
          changedBy: 'manager_1',
        );

    test('periodKey espelha paymentPeriodKey', () {
      final r = record(year: 2026, month: 8, status: PaymentStatus.paid);
      expect(r.periodKey, '2026-08');
    });

    test('isOverdue só é true para status overdue', () {
      expect(
        record(year: 2026, month: 8, status: PaymentStatus.overdue).isOverdue,
        isTrue,
      );
      expect(
        record(year: 2026, month: 8, status: PaymentStatus.paidLate).isOverdue,
        isFalse,
      );
      expect(
        record(year: 2026, month: 8, status: PaymentStatus.paid).isOverdue,
        isFalse,
      );
    });

    test('Equatable — dois registos com os mesmos campos são iguais', () {
      final a = record(year: 2026, month: 8, status: PaymentStatus.paid);
      final b = record(year: 2026, month: 8, status: PaymentStatus.paid);
      expect(a, equals(b));
    });

    test('Equatable — status diferente torna-os diferentes', () {
      final a = record(year: 2026, month: 8, status: PaymentStatus.paid);
      final b = record(year: 2026, month: 8, status: PaymentStatus.overdue);
      expect(a, isNot(equals(b)));
    });
  });
}
