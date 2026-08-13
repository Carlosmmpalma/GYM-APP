import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/manage_plans_screen.dart';

const _tenantId = 'tenant_test';

/// Testa a mesma coisa que a Fase 3 pedia manualmente em Chrome, agora
/// automatizado: `ManagePlansScreen` só depende de Firestore (não de
/// Cloud Functions, ao contrário de `AssignSubscriptionScreen`), por
/// isso `fake_cloud_firestore` chega — sem precisar de mockar nada.
void main() {
  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: const MaterialApp(home: ManagePlansScreen()),
    );
  }

  testWidgets('lista vazia mostra a mensagem de "nenhum plano"',
      (tester) async {
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Ainda não existe nenhum plano'),
      findsOneWidget,
    );
  });

  testWidgets('criar um plano novo faz aparecer na lista', (tester) async {
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Premium');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Preço atual'),
      '59.90',
    );
    // Descrição fica vazia (não obrigatória) e a moeda mantém o valor
    // por omissão do controller ("EUR").
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('59.90 EUR'), findsOneWidget);

    // Confirma também que ficou realmente persistido no Firestore, não
    // só na UI otimista — lê diretamente a coleção.
    final snapshot = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('plans')
        .get();
    expect(snapshot.docs, hasLength(1));
    expect(snapshot.docs.first.data()['name'], 'Premium');
    expect(snapshot.docs.first.data()['currentPrice'], 59.90);
    expect(snapshot.docs.first.data()['currency'], 'EUR');
    expect(snapshot.docs.first.data()['active'], isTrue);
  });

  testWidgets('criar um plano sem nome mostra erro de validação e não escreve nada',
      (tester) async {
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Preço atual'),
      '10',
    );
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    // O diálogo continua aberto (validação falhou, não fechou).
    expect(find.text('Obrigatório'), findsOneWidget);
    expect(find.text('Novo plano'), findsOneWidget);

    final snapshot = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('plans')
        .get();
    expect(snapshot.docs, isEmpty);
  });
}
