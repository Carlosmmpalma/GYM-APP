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
import 'package:gym_saas/presentation/screens/my_bookings_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

const _tenantId = 'tenant_test';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  testWidgets('estado vazio quando não há marcações', (tester) async {
    final firestore = FakeFirebaseFirestore();
    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tenantAppConfigProvider.overrideWithValue(
            const TenantAppConfig(tenantId: _tenantId),
          ),
          firestoreProvider.overrideWithValue(firestore),
          currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
        ],
        child: const MaterialApp(home: Scaffold(body: MyBookingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ainda não tens nenhuma marcação.'), findsOneWidget);
  });

  testWidgets('mostra uma marcação ativa e permite cancelar', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_1')
        .set({
      'serviceId': 'service_1',
      'startAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10)),
      'endAt': Timestamp.fromDate(DateTime(2026, 1, 1, 11)),
      'capacity': 5,
      'status': 'scheduled',
      'activeBookingCount': 1,
    });
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_1')
        .collection('bookings')
        .doc('member_1')
        .set({
      'memberId': 'member_1',
      'status': 'booked',
      'source': 'self',
      'isExtra': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });

    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tenantAppConfigProvider.overrideWithValue(
            const TenantAppConfig(tenantId: _tenantId),
          ),
          firestoreProvider.overrideWithValue(firestore),
          currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
        ],
        child: const MaterialApp(home: Scaffold(body: MyBookingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Marcação #'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Ainda não tens nenhuma marcação.'), findsOneWidget);
  });
}
