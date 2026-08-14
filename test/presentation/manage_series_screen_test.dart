import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/manage_series_screen.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

/// Mesma justificação de `book_training_screen_test.dart`: nenhum dos
/// caminhos exercitados aqui (listar séries, navegar para o detalhe)
/// chega a chamar uma Cloud Function — `sessionSeriesRepositoryProvider`
/// exige `functionsProvider` no construtor na mesma, por isso um mock
/// nunca invocado chega.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Hyrox', 'active': true});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionSeries')
        .doc('series_active')
        .set({
      'serviceId': 'service_1',
      'instructorId': null,
      'dayOfWeek': DateTime.monday,
      'startTime': '18:00',
      'durationMinutes': 60,
      'capacity': 6,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 5)),
      'preAssignedMemberIds': <String>[],
      'status': 'active',
    });

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionSeries')
        .doc('series_cancelled')
        .set({
      'serviceId': 'service_1',
      'instructorId': null,
      'dayOfWeek': DateTime.wednesday,
      'startTime': '19:00',
      'durationMinutes': 60,
      'capacity': 2,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 7)),
      'preAssignedMemberIds': <String>[],
      'status': 'cancelled',
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
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
      ],
      child: const MaterialApp(home: ManageSeriesScreen()),
    );
  }

  testWidgets('lista vazia mostra mensagem de estado vazio', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Ainda não existe nenhuma série'), findsOneWidget);
  });

  testWidgets('mostra série ativa e série cancelada com os dados corretos',
      (tester) async {
    final firestore = await seedFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Hyrox'), findsNWidgets(2));
    expect(find.text('Segunda · 18:00 · Grupo (6)'), findsOneWidget);
    expect(find.text('Quarta · 19:00 · Duo · cancelada'), findsOneWidget);
  });

  testWidgets('tocar numa série abre o detalhe com o botão "Gerar agora"',
      (tester) async {
    final firestore = await seedFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Segunda · 18:00 · Grupo (6)'));
    await tester.pumpAndSettle();

    expect(find.text('Gerar agora'), findsOneWidget);
    expect(find.text('Cancelar série'), findsOneWidget);
    expect(find.text('Série ativa'), findsOneWidget);
  });
}
