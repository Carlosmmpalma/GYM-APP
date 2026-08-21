import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/manage_payments_screen.dart';

const _tenantId = 'tenant_test';

void main() {
  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
              uid: 'manager_1',
              tenantId: _tenantId,
              roles: {Role.manager},
            ),
          ),
        ),
      ],
      // `currentAppUserProvider` precisa de já estar resolvido quando
      // `_markStatus` faz `ref.read` — mesmo truque de
      // `occurrence_detail_screen_test.dart` (Fase 6).
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(currentAppUserProvider);
            return const ManagePaymentsScreen();
          },
        ),
      ),
    );
  }

  Future<FakeFirebaseFirestore> seedMembers() async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    final thisMonth = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc('member_paid')
        .set({
      'name': 'Rita Ferreira',
      'memberNumber': '000001',
      'currentPaymentStatus': 'paid',
      'currentPaymentPeriod': thisMonth,
    });
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc('member_no_record')
        .set({'name': 'Beatriz Sousa', 'memberNumber': '000002'});

    return firestore;
  }

  testWidgets(
      'Fase 9 (UC27 fechado) — mostra "Sem registo" para quem não tem marcação este mês',
      (tester) async {
    final firestore = await seedMembers();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Pago'), findsOneWidget);
    expect(find.text('Sem registo'), findsOneWidget);
  });

  testWidgets(
      'Fase 9 (UC27 fechado) — marcar "Em atraso" grava o registo e denormaliza',
      (tester) async {
    final firestore = await seedMembers();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beatriz Sousa'));
    await tester.pumpAndSettle();

    expect(find.text('Em atraso'), findsOneWidget);
    await tester.tap(find.text('Em atraso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc('member_no_record')
        .get();
    expect(doc.data()?['currentPaymentStatus'], 'overdue');

    // A lista reflete o pill novo imediatamente (stream reativo).
    expect(find.text('Em atraso'), findsOneWidget);
  });
}
