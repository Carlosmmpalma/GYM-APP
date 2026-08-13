import 'package:cloud_firestore/cloud_firestore.dart';
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

const _tenantId = 'tenant_test';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> seedFirestore({required int capacity}) async {
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
    return firestore;
  }

  testWidgets('mostra a sessão com vagas e permite marcar', (tester) async {
    final firestore = await seedFirestore(capacity: 1);
    const appUser = AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tenantAppConfigProvider.overrideWithValue(
            const TenantAppConfig(tenantId: _tenantId),
          ),
          firestoreProvider.overrideWithValue(firestore),
          currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
        ],
        child: const MaterialApp(home: Scaffold(body: BookTrainingScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 vaga(s) de 1'), findsOneWidget);
    expect(find.text('Marcar'), findsOneWidget);

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    expect(find.text('Sem vagas'), findsWidgets);
  });
}
