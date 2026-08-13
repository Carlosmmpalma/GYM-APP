import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/usage_rule.dart';

void main() {
  group('UsageRule', () {
    test('unlimited: isUnlimited true, describe() sem limite/período', () {
      const rule = UsageRule.unlimited();
      expect(rule.isUnlimited, isTrue);
      expect(rule.limit, isNull);
      expect(rule.period, isNull);
      expect(rule.describe(), 'Ilimitado');
    });

    test('limited: isUnlimited false, describe() inclui limite e período', () {
      const rule = UsageRule.limited(limit: 3, period: UsagePeriod.week);
      expect(rule.isUnlimited, isFalse);
      expect(rule.limit, 3);
      expect(rule.period, UsagePeriod.week);
      expect(rule.describe(), '3 x / semana');
    });

    test('describe() traduz cada período', () {
      expect(
        const UsageRule.limited(limit: 1, period: UsagePeriod.day).describe(),
        '1 x / dia',
      );
      expect(
        const UsageRule.limited(limit: 2, period: UsagePeriod.month).describe(),
        '2 x / mês',
      );
    });

    test('duas UsageRule iguais (Equatable) são ==', () {
      expect(
        const UsageRule.limited(limit: 3, period: UsagePeriod.week),
        const UsageRule.limited(limit: 3, period: UsagePeriod.week),
      );
      expect(const UsageRule.unlimited(), const UsageRule.unlimited());
    });

    test('UsagePeriod.fromValue reconhece os 3 valores e rejeita o resto', () {
      expect(UsagePeriod.fromValue('day'), UsagePeriod.day);
      expect(UsagePeriod.fromValue('week'), UsagePeriod.week);
      expect(UsagePeriod.fromValue('month'), UsagePeriod.month);
      expect(() => UsagePeriod.fromValue('year'), throwsArgumentError);
    });
  });
}
