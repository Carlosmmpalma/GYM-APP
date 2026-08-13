import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/subscription.dart';

Subscription _sub({
  required SubscriptionStatus status,
  required Set<String> activeServiceIds,
}) {
  return Subscription(
    id: 'sub_1',
    memberId: 'member_1',
    planId: 'plan_1',
    status: status,
    startDate: DateTime(2026, 1, 1),
    agreedPrice: 30,
    currency: 'EUR',
    activeServiceIds: activeServiceIds,
  );
}

void main() {
  group('Subscription.grantsAccessTo', () {
    test('ativa + serviço incluído → true', () {
      final sub = _sub(
        status: SubscriptionStatus.active,
        activeServiceIds: {'service_a'},
      );
      expect(sub.grantsAccessTo('service_a'), isTrue);
    });

    test('ativa + serviço NÃO incluído → false', () {
      final sub = _sub(
        status: SubscriptionStatus.active,
        activeServiceIds: {'service_a'},
      );
      expect(sub.grantsAccessTo('service_b'), isFalse);
    });

    test('cancelled, mesmo com o serviço na lista → false (Domain Model v1 §16)', () {
      final sub = _sub(
        status: SubscriptionStatus.cancelled,
        activeServiceIds: {'service_a'},
      );
      expect(sub.grantsAccessTo('service_a'), isFalse);
    });

    test('paused → false', () {
      final sub = _sub(
        status: SubscriptionStatus.paused,
        activeServiceIds: {'service_a'},
      );
      expect(sub.grantsAccessTo('service_a'), isFalse);
    });

    test('expired → false', () {
      final sub = _sub(
        status: SubscriptionStatus.expired,
        activeServiceIds: {'service_a'},
      );
      expect(sub.grantsAccessTo('service_a'), isFalse);
    });

    test('isActive reflete só o status', () {
      expect(
        _sub(status: SubscriptionStatus.active, activeServiceIds: const {}).isActive,
        isTrue,
      );
      expect(
        _sub(status: SubscriptionStatus.paused, activeServiceIds: const {}).isActive,
        isFalse,
      );
    });
  });

  group('SubscriptionServiceConflictException.toString()', () {
    test('com nomes de serviços em conflito, lista-os', () {
      const exception = SubscriptionServiceConflictException(['Aula de Grupo', 'Pilates']);
      expect(exception.toString(), contains('Aula de Grupo'));
      expect(exception.toString(), contains('Pilates'));
    });

    test('sem nomes (fallback), ainda dá uma mensagem não vazia', () {
      const exception = SubscriptionServiceConflictException([]);
      expect(exception.toString(), isNotEmpty);
    });
  });
}
