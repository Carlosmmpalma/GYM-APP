import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/booking_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/usage.dart';
import 'package:gym_saas/presentation/screens/member_detail_screen.dart';
import 'package:gym_saas/repositories/usage_repository.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

// `subscriptionRepositoryProvider` não é sobreposto neste teste — a
// leitura de subscriptions (`watchMemberSubscriptions`) é direta ao
// Firestore, mesmo padrão de outros ecrãs. O construtor de
// `FirebaseSubscriptionRepository` exige na mesma um `FirebaseFunctions`
// (nunca invocado por este ecrã, que só lê) — mock nunca chamado chega,
// mesmo raciocínio documentado em `book_training_screen_test.dart`.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

// Task #63 — `recalculateUsage.ts` (Cloud Function) nunca tinha UI.
// Testar o botão sem mockar `cloud_functions` diretamente: um fake do
// repository, mesmo padrão já provado nos testes de booking da Fase 4.
class _FakeUsageRepository implements UsageRepository {
  _FakeUsageRepository({this.recalculationResult = const []});

  final List<UsageRecalculationEntry> recalculationResult;

  @override
  Stream<Usage?> watchUsage({
    required String memberId,
    required String serviceId,
    required String period,
  }) =>
      const Stream.empty();

  @override
  Future<List<UsageRecalculationEntry>> recalculateUsage({
    required String memberId,
    required String serviceId,
  }) async =>
      recalculationResult;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc('member_1')
        .set({'memberNumber': 'M001', 'name': 'Ana Membro', 'status': 'active'});
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('plans')
        .doc('plan_1')
        .set({
      'name': 'Plano Standard',
      'description': '',
      'currentPrice': 30,
      'currency': 'EUR',
      'active': true,
    });
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aula de Grupo', 'active': true});
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('subscriptions')
        .doc('sub_1')
        .set({
      'memberId': 'member_1',
      'planId': 'plan_1',
      'status': 'active',
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'agreedPrice': 30,
      'currency': 'EUR',
      'activeServiceIds': ['service_1'],
    });
    return firestore;
  }

  Widget buildApp(
    FakeFirebaseFirestore firestore,
    _FakeUsageRepository usageRepository,
  ) {
    const member = MemberSummary(
      uid: 'member_1',
      memberNumber: 'M001',
      name: 'Ana Membro',
      active: true,
    );
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        usageRepositoryProvider.overrideWithValue(usageRepository),
      ],
      child: const MaterialApp(home: MemberDetailScreen(member: member)),
    );
  }

  testWidgets(
      'recalcula a utilização de um serviço único e mostra o resultado num diálogo',
      (tester) async {
    final firestore = await seedFirestore();
    final usageRepository = _FakeUsageRepository(
      recalculationResult: const [(period: '2026-W33', used: 2)],
    );

    await tester.pumpWidget(buildApp(firestore, usageRepository));
    await tester.pumpAndSettle();

    expect(find.text('Recalcular utilização'), findsOneWidget);

    // Só um serviço ativo (`service_1`) — não há picker, chama direto.
    await tester.tap(find.text('Recalcular utilização'));
    await tester.pumpAndSettle();

    expect(find.text('Utilização recalculada — Aula de Grupo'), findsOneWidget);
    expect(find.text('2026-W33: 2 sessão(ões)'), findsOneWidget);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    expect(find.text('Utilização recalculada — Aula de Grupo'), findsNothing);
  });

  testWidgets('mostra mensagem própria quando não há nada para recalcular',
      (tester) async {
    final firestore = await seedFirestore();
    final usageRepository = _FakeUsageRepository(recalculationResult: const []);

    await tester.pumpWidget(buildApp(firestore, usageRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recalcular utilização'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Nada para recalcular'),
      findsOneWidget,
    );
  });
}
