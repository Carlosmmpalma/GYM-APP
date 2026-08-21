import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/manage_services_screen.dart';

const _tenantId = 'tenant_test';

void main() {
  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: const MaterialApp(home: ManageServicesScreen()),
    );
  }

  testWidgets(
      'Fase 8 (UC26 fechado) — criar um serviço com grupo exclusivo grava o campo',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'), 'Sem acompanhamento');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Grupo exclusivo (opcional)'),
        'sala');
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    final snap = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.first.data()['name'], 'Sem acompanhamento');
    expect(snap.docs.first.data()['exclusiveGroup'], 'sala');

    expect(find.textContaining('Grupo exclusivo: sala'), findsOneWidget);
  });

  testWidgets(
      'Fase 8 (UC26 fechado) — editar um serviço existente atualiza nome/grupo',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Hyrox', 'active': true, 'exclusiveGroup': null});

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.textContaining('Grupo exclusivo'), findsNothing);

    await tester.tap(find.text('Hyrox'));
    await tester.pumpAndSettle();

    expect(find.text('Editar serviço'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Grupo exclusivo (opcional)'),
        'sala');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .get();
    expect(doc.data()?['exclusiveGroup'], 'sala');
    expect(find.textContaining('Grupo exclusivo: sala'), findsOneWidget);
  });
}
