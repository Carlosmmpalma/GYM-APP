import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/manage_modalities_screen.dart';

const _tenantId = 'tenant_test';

void main() {
  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aulas de Grupo', 'active': true});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('modalities')
        .doc('modality_1')
        .set({
      'name': 'Pilates',
      'active': true,
      'serviceIds': ['service_1'],
    });

    return firestore;
  }

  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: const MaterialApp(home: ManageModalitiesScreen()),
    );
  }

  testWidgets('lista vazia mostra a mensagem de "nenhuma modalidade"',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ainda não há modalidades'), findsOneWidget);
  });

  testWidgets('mostra a modalidade seedada com a contagem de serviços',
      (tester) async {
    final firestore = await seedFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Pilates'), findsOneWidget);
    expect(find.text('1 serviço(s)'), findsOneWidget);
  });

  testWidgets('criar uma modalidade nova faz aparecer na lista',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Hyrox');
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(find.text('Hyrox'), findsOneWidget);
    expect(find.text('0 serviço(s)'), findsOneWidget);
  });

  testWidgets('abrir o detalhe e ligar o serviço grava serviceIds no Firestore',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aulas de Grupo', 'active': true});
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('modalities')
        .doc('modality_1')
        .set({'name': 'Pilates', 'active': true, 'serviceIds': <String>[]});

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pilates'));
    await tester.pumpAndSettle();

    expect(find.text('Aulas de Grupo'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pumpAndSettle();

    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('modalities')
        .doc('modality_1')
        .get();
    expect((doc.data()!['serviceIds'] as List), contains('service_1'));
  });
}
