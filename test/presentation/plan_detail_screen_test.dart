import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/plan.dart';
import 'package:gym_saas/presentation/screens/plan_detail_screen.dart';

const _tenantId = 'tenant_test';

const _plan = Plan(
  id: 'plan_1',
  name: 'Standard',
  description: 'Plano de teste',
  currentPrice: 30,
  currency: 'EUR',
  active: true,
);

/// `PlanDetailScreen` só depende de Firestore (`planRepositoryProvider`
/// via `servicesProvider`/`planServicesProvider`) — mesmo raciocínio de
/// `manage_plans_screen_test.dart`, sem precisar de mockar Cloud
/// Functions.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aula de Grupo', 'active': true});
    return firestore;
  }

  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        // Fase 11 — `FirebasePlanRepository` passou a precisar de
        // Functions (`syncPlanSubscriptions`, para propagar alterações
        // ao plano a quem já o tem). Sem este override, o construtor
        // tenta `FirebaseFunctions.instanceFor` e rebenta com "No
        // Firebase App" — o ecrã ficava em erro e os finders não
        // encontravam nada. Um mock nunca invocado chega: nenhum destes
        // testes exercita a sincronização.
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
      ],
      child: const MaterialApp(home: PlanDetailScreen(plan: _plan)),
    );
  }

  testWidgets('service ainda não incluído aparece desligado', (tester) async {
    final firestore = await seedFirestore();

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Aula de Grupo'), findsOneWidget);
    expect(find.text('Não incluído'), findsOneWidget);

    // `find.byType(SwitchListTile)` sozinho já não é único: o ecrã
    // ganhou um segundo switch ("Plano ativo", extensão pedida depois
    // desta suite ter sido escrita — ver README). Localiza pelo texto
    // do service para apanhar só o switch do "Aula de Grupo".
    final switchWidget = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Aula de Grupo'),
    );
    expect(switchWidget.value, isFalse);
  });

  testWidgets('ligar o switch e escolher "Ilimitado" associa o service',
      (tester) async {
    final firestore = await seedFirestore();

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Aula de Grupo'));
    await tester.pumpAndSettle();

    // O diálogo abre com "Ilimitado" já selecionado por omissão.
    expect(find.text('Regra de utilização'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Ilimitado'), findsOneWidget);

    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('plans')
        .doc('plan_1')
        .collection('services')
        .doc('service_1')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['enabled'], isTrue);
    expect(doc.data()!['usage']['type'], 'unlimited');
  });

  testWidgets('ligar o switch e escolher "Limitado" grava limit/período',
      (tester) async {
    final firestore = await seedFirestore();

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Aula de Grupo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Limitado'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantidade'), '2');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('2 x / semana'), findsOneWidget);

    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('plans')
        .doc('plan_1')
        .collection('services')
        .doc('service_1')
        .get();
    expect(doc.data()!['usage']['type'], 'limited');
    expect(doc.data()!['usage']['limit'], 2);
    expect(doc.data()!['usage']['period'], 'week');
  });
}
