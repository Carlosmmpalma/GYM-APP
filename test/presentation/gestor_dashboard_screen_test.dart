import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/gestor_dashboard_screen.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

// Nenhum caminho exercitado por este ecrã chama uma Cloud Function
// (lê tudo diretamente do Firestore) — mesmo padrão de
// `manage_series_screen_test.dart`: um mock nunca invocado chega, os
// construtores dos repositórios exigem `FirebaseFunctions` na mesma.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);

    for (final entry in [
      ('member_1', 'active'),
      ('member_2', 'active'),
      ('member_3', 'active'),
      ('member_4', 'inactive'),
    ]) {
      await tenant.collection('members').doc(entry.$1).set({
        'memberNumber': entry.$1,
        'name': entry.$1,
        'status': entry.$2,
      });
    }

    await tenant.collection('sessionSeries').doc('series_active').set({
      'serviceId': 'service_1',
      'dayOfWeek': 1,
      'startTime': '18:00',
      'durationMinutes': 60,
      'capacity': 6,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'preAssignedMemberIds': <String>[],
      'status': 'active',
    });
    await tenant.collection('sessionSeries').doc('series_cancelled').set({
      'serviceId': 'service_1',
      'dayOfWeek': 3,
      'startTime': '19:00',
      'durationMinutes': 60,
      'capacity': 4,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'preAssignedMemberIds': <String>[],
      'status': 'cancelled',
    });

    final now = DateTime.now();
    Future<void> occurrence(
      String id, {
      required Duration offset,
      required int capacity,
      required int activeBookingCount,
      required String status,
    }) {
      return tenant.collection('sessionOccurrences').doc(id).set({
        'serviceId': 'service_1',
        'startAt': Timestamp.fromDate(now.add(offset)),
        'endAt': Timestamp.fromDate(now.add(offset + const Duration(hours: 1))),
        'capacity': capacity,
        'activeBookingCount': activeBookingCount,
        'status': status,
      });
    }

    // 2 dentro dos próximos 7 dias, "scheduled" — 50% e 100% de
    // ocupação, média 75%.
    await occurrence(
      'occ_in_range_1',
      offset: const Duration(days: 1),
      capacity: 10,
      activeBookingCount: 5,
      status: 'scheduled',
    );
    await occurrence(
      'occ_in_range_2',
      offset: const Duration(days: 2),
      capacity: 10,
      activeBookingCount: 10,
      status: 'scheduled',
    );
    // Cancelada dentro da janela — não deve contar para "Sessões" nem
    // para a ocupação média.
    await occurrence(
      'occ_cancelled_in_range',
      offset: const Duration(days: 3),
      capacity: 5,
      activeBookingCount: 2,
      status: 'cancelled',
    );
    // Fora da janela de 7 dias — não deve aparecer em lado nenhum.
    await occurrence(
      'occ_out_of_range',
      offset: const Duration(days: 10),
      capacity: 10,
      activeBookingCount: 1,
      status: 'scheduled',
    );

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
      child: const MaterialApp(home: GestorDashboardScreen()),
    );
  }

  testWidgets('agrega membros ativos, séries ativas, sessões e ocupação média',
      (tester) async {
    final firestore = await seedFirestore();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Membros ativos'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // membros ativos
    expect(find.text('Séries ativas'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // séries ativas
    expect(find.text('Sessões (próx. 7 dias)'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // só as scheduled dentro da janela
    expect(find.text('Ocupação média'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });
}
