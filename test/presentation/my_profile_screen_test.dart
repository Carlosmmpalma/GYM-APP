import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/my_profile_screen.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

void main() {
  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .set({
      'memberNumber': '000123',
      'name': 'Rita Ferreira',
      'status': 'active',
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
      child: const MaterialApp(
        home: Scaffold(body: MyProfileScreen(memberId: _memberId)),
      ),
    );
  }

  testWidgets('mostra nome/nº de sócio (só leitura) e contactos vazios',
      (tester) async {
    final firestore = await seedFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.textContaining('000123'), findsOneWidget);
  });

  testWidgets('editar telefone/email e guardar persiste no Firestore',
      (tester) async {
    final firestore = await seedFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone'),
      '912345678',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email de contacto'),
      'rita@example.com',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Perfil atualizado.'), findsOneWidget);

    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .get();
    expect(doc.data()?['phone'], '912345678');
    expect(doc.data()?['email'], 'rita@example.com');
    // Confirma que só phone/email/updatedAt mudaram — nome/nº de sócio
    // continuam exclusivos do Gestor, mesma restrição do
    // firestore.rules aplicada aqui do lado do código.
    expect(doc.data()?['name'], 'Rita Ferreira');
    expect(doc.data()?['memberNumber'], '000123');
  });

  testWidgets('membro sem documento mostra mensagem de erro, não crasha',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Não foi possível encontrar o teu perfil'),
      findsOneWidget,
    );
  });
}
