import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/book_training_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

// Fase 3: bookSessionUseCaseProvider passa a depender de
// subscriptionRepositoryProvider, que por sua vez depende de
// functionsProvider — mesmo que a query de elegibilidade em si só toque
// no Firestore (createSubscription é que usaria Functions), o provider
// é construído na mesma, e FirebaseFunctions.instance real lançaria
// "no Firebase App" nestes testes (nunca chamamos Firebase.initializeApp
// aqui). Um mock nunca invocado chega.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> seedFirestore({
    required int capacity,
    bool memberIsEligible = true,
  }) async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aula de Grupo', 'active': true});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_1')
        .set({
      'serviceId': 'service_1',
      'startAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
      'endAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1, hours: 1))),
      'capacity': capacity,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });

    // Fase 3 — UC06/07/08/09: só marca quem tem uma subscription ativa
    // que dá acesso a este serviço.
    if (memberIsEligible) {
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('subscriptions')
          .doc('sub_1')
          .set({
        'memberId': 'member_1',
        'planId': 'plan_1',
        'status': 'active',
        'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'agreedPrice': 50,
        'currency': 'EUR',
        'activeServiceIds': ['service_1'],
      });
    }

    return firestore;
  }

  Widget buildApp(FakeFirebaseFirestore firestore, AppUser appUser) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
      ],
      child: const MaterialApp(home: Scaffold(body: BookTrainingScreen())),
    );
  }

  testWidgets('mostra a sessão com vagas e permite marcar quando elegível',
      (tester) async {
    final firestore = await seedFirestore(capacity: 1);
    const appUser = AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('1 vaga(s) de 1'), findsOneWidget);
    expect(find.text('Marcar'), findsOneWidget);

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    expect(find.text('Sem vagas'), findsWidgets);
  });

  testWidgets(
      'bloqueia a marcação com mensagem própria quando o membro não é elegível',
      (tester) async {
    final firestore = await seedFirestore(capacity: 1, memberIsEligible: false);
    const appUser = AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não tens um plano ativo que dê acesso a este serviço.'),
      findsOneWidget,
    );
    // A ocorrência continua com a vaga livre — o bloqueio acontece antes
    // de sequer tentar a transação de booking.
    expect(find.text('1 vaga(s) de 1'), findsOneWidget);
  });
}
