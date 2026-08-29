import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/manage_services_screen.dart';
import 'package:gym_saas/application/providers/plan_providers.dart';
import 'package:gym_saas/repositories/catalogue_admin_repository.dart';

const _tenantId = 'tenant_test';

/// A eliminação em si vive numa Cloud Function e está coberta a sério
/// em `firebase/tests/delete-catalogue-entry.test.ts` (é lá que a
/// contagem de referências e as recusas são exercitadas contra
/// Firestore real). Aqui interessa a outra metade: o que o Gestor VÊ
/// quando a eliminação é recusada. Um "não foi possível" seco é
/// exatamente a mensagem que o obriga a pedir ajuda a alguém.
class _FakeCatalogueAdminRepository implements CatalogueAdminRepository {
  _FakeCatalogueAdminRepository({this.blockers});

  final List<String>? blockers;
  ({CatalogueKind kind, String id})? lastDelete;

  @override
  Future<void> delete({
    required CatalogueKind kind,
    required String id,
  }) async {
    lastDelete = (kind: kind, id: id);
    if (blockers != null) throw CatalogueEntryInUseException(blockers!);
  }
}

void main() {
  Widget buildApp(
    FakeFirebaseFirestore firestore, {
    CatalogueAdminRepository? catalogueAdmin,
  }) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        if (catalogueAdmin != null)
          catalogueAdminRepositoryProvider.overrideWithValue(catalogueAdmin),
      ],
      child: const MaterialApp(home: ManageServicesScreen()),
    );
  }

  Future<FakeFirebaseFirestore> seedService() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('svc_1')
        .set({'name': 'Aulas de grupo', 'active': true});
    return firestore;
  }

  /// O caixote do lixo solto na linha virou menu `⋮`: em telemóvel, o
  /// dedo tapa a linha toda e um toque acidental numa ação sem retorno
  /// é caro. Dois gestos deliberados antes de sequer ver a confirmação.
  Future<void> openRowMenu(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
  }

  testWidgets('eliminar um serviço pede confirmação primeiro', (tester) async {
    final repository = _FakeCatalogueAdminRepository();
    await tester
        .pumpWidget(buildApp(await seedService(), catalogueAdmin: repository));
    await tester.pumpAndSettle();

    await openRowMenu(tester);

    expect(find.text('Eliminar Aulas de grupo?'), findsOneWidget);

    // Desistir não chama nada.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.lastDelete, isNull);

    await openRowMenu(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(repository.lastDelete?.kind, CatalogueKind.service);
    expect(repository.lastDelete?.id, 'svc_1');
  });

  testWidgets('quando é recusado, mostra O QUÊ é que depende do serviço',
      (tester) async {
    final repository = _FakeCatalogueAdminRepository(blockers: [
      '3 série(s) de aulas',
      '12 subscrição(ões) de membros',
    ]);
    await tester
        .pumpWidget(buildApp(await seedService(), catalogueAdmin: repository));
    await tester.pumpAndSettle();

    await openRowMenu(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('está a ser usado'), findsOneWidget);
    expect(find.textContaining('3 série(s) de aulas'), findsOneWidget);
    expect(
        find.textContaining('12 subscrição(ões) de membros'), findsOneWidget);
    // E diz o que fazer em vez disso.
    expect(find.textContaining('Desativar'), findsOneWidget);
  });

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
