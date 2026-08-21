import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/member_home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Fase 10 — o dashboard "Início" do Aluno (mockup). Testa os três
/// blocos: estado da conta, próxima marcação e atalhos.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> seed({
    String? paymentStatus,
    String? paymentPeriod,
    bool withPlan = true,
  }) async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);

    await tenant.collection('members').doc(_memberId).set({
      'memberNumber': '000142',
      'name': 'Rita Ferreira',
      'status': 'active',
      if (paymentStatus != null) 'currentPaymentStatus': paymentStatus,
      if (paymentPeriod != null) 'currentPaymentPeriod': paymentPeriod,
    });

    if (withPlan) {
      await tenant.collection('plans').doc('plan_plus').set({
        'name': 'Plus',
        'active': true,
        // `Plan._fromDoc` exige `currentPrice` (cast não-nulo) — sem
        // isto o `plansProvider` fica em erro e o card cai no `planId`
        // em vez do nome do plano.
        'currentPrice': 30.0,
        'currency': 'EUR',
      });
      await tenant.collection('subscriptions').doc('sub_1').set({
        'memberId': _memberId,
        'planId': 'plan_plus',
        'status': 'active',
        'startDate': Timestamp.now(),
        'agreedPrice': 30.0,
        'currency': 'EUR',
        'activeServiceIds': <String>[],
      });
    }

    return firestore;
  }

  Widget buildApp(
    FakeFirebaseFirestore firestore, {
    ValueChanged<int>? onOpenTab,
  }) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
              uid: _memberId,
              tenantId: _tenantId,
              roles: {Role.member},
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MemberHomeScreen(
            memberId: _memberId,
            onOpenTab: onOpenTab ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('mostra nº de sócio e o plano ativo no card de conta',
      (tester) async {
    final firestore = await seed();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.textContaining('000142'), findsOneWidget);
    expect(find.text('Plus'), findsOneWidget);
  });

  testWidgets('sem subscription ativa mostra "Sem plano ativo"',
      (tester) async {
    final firestore = await seed(withPlan: false);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Sem plano ativo'), findsOneWidget);
  });

  group('pill da mensalidade', () {
    testWidgets('pago este mês → "Em dia"', (tester) async {
      final now = DateTime.now();
      final period = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final firestore =
          await seed(paymentStatus: 'paid', paymentPeriod: period);

      await tester.pumpWidget(buildApp(firestore));
      await tester.pumpAndSettle();

      expect(find.text('Em dia'), findsOneWidget);
    });

    testWidgets('sem registo nenhum → "Sem registo", nunca alarme',
        (tester) async {
      final firestore = await seed();
      await tester.pumpWidget(buildApp(firestore));
      await tester.pumpAndSettle();

      expect(find.text('Sem registo'), findsOneWidget);
      expect(find.text('Em atraso'), findsNothing);
    });

    testWidgets('overdue de um mês ANTERIOR não aparece como em atraso',
        (tester) async {
      final firestore =
          await seed(paymentStatus: 'overdue', paymentPeriod: '2000-01');

      await tester.pumpWidget(buildApp(firestore));
      await tester.pumpAndSettle();

      expect(find.text('Sem registo'), findsOneWidget);
      expect(find.text('Em atraso'), findsNothing);
    });
  });

  testWidgets('sem marcações mostra o estado vazio', (tester) async {
    final firestore = await seed();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não tens nenhuma marcação'), findsOneWidget);
  });

  testWidgets('os quatro atalhos do mockup estão presentes', (tester) async {
    final firestore = await seed();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('O meu plano'), findsOneWidget);
    expect(find.text('Marcar treino'), findsOneWidget);
    expect(find.text('Avaliações'), findsOneWidget);
    expect(find.text('Minhas marcações'), findsOneWidget);
  });

  testWidgets('atalhos que são separadores trocam de tab em vez de navegar',
      (tester) async {
    final firestore = await seed();
    var openedTab = -1;
    await tester.pumpWidget(
      buildApp(firestore, onOpenTab: (index) => openedTab = index),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcar treino'));
    expect(openedTab, 1);

    await tester.tap(find.text('Minhas marcações'));
    expect(openedTab, 3);
  });
}
