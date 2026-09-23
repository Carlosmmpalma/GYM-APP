import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/core/utils/iso_week.dart';
import 'package:gym_saas/domain/entities/service.dart';
import 'package:gym_saas/presentation/widgets/weekly_allowance.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

class _FakeFunctions extends Mock implements FirebaseFunctions {}

/// "O que ainda posso marcar esta semana?" — o resumo no topo do ecrã de
/// marcar.
void main() {
  Future<FakeFirebaseFirestore> semear({
    required int limiteAulas,
    int usadas = 0,
    bool hyroxIlimitado = true,
  }) async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);

    await tenant
        .collection('services')
        .doc('svc_aulas')
        .set({'name': 'Aulas de grupo', 'active': true});
    await tenant
        .collection('services')
        .doc('svc_hyrox')
        .set({'name': 'Hyrox', 'active': true});

    await tenant.collection('plans').doc('plan_1').set({
      'name': 'Premium',
      'description': '',
      'currentPrice': 60.0,
      'currency': 'EUR',
      'active': true,
    });
    await tenant
        .collection('plans')
        .doc('plan_1')
        .collection('services')
        .doc('svc_aulas')
        .set({
      'enabled': true,
      'usage': {'type': 'limited', 'limit': limiteAulas, 'period': 'week'},
    });
    await tenant
        .collection('plans')
        .doc('plan_1')
        .collection('services')
        .doc('svc_hyrox')
        .set({
      'enabled': true,
      'usage': hyroxIlimitado
          ? {'type': 'unlimited'}
          : {'type': 'limited', 'limit': 2, 'period': 'week'},
    });

    await tenant.collection('subscriptions').doc('sub_1').set({
      'memberId': _memberId,
      'planId': 'plan_1',
      'status': 'active',
      'startDate': Timestamp.now(),
      'agreedPrice': 60.0,
      'currency': 'EUR',
      'activeServiceIds': ['svc_aulas', 'svc_hyrox'],
    });

    if (usadas > 0) {
      final semana = isoWeekKey(DateTime.now());
      await tenant
          .collection('usage')
          .doc('${_memberId}_svc_aulas_$semana')
          .set({
        'memberId': _memberId,
        'serviceId': 'svc_aulas',
        'period': semana,
        'used': usadas,
      });
    }

    return firestore;
  }

  Widget app(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_FakeFunctions()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: WeeklyAllowance(
            memberId: _memberId,
            serviceIds: {'svc_aulas', 'svc_hyrox'},
            servicesById: {
              'svc_aulas': Service(
                id: 'svc_aulas',
                name: 'Aulas de grupo',
                active: true,
              ),
              'svc_hyrox': Service(
                id: 'svc_hyrox',
                name: 'Hyrox',
                active: true,
              ),
            },
          ),
        ),
      ),
    );
  }

  testWidgets('diz quantas SOBRAM, não quantas foram gastas', (tester) async {
    // "Restam 2" responde à pergunta. "1/3 usadas" obriga a fazer a
    // conta, e a conta é feita com o telemóvel na mão à porta do
    // ginásio.
    await tester.pumpWidget(app(await semear(limiteAulas: 3, usadas: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('restam 2'), findsOneWidget);
  });

  testWidgets('o singular é escrito por extenso', (tester) async {
    await tester.pumpWidget(app(await semear(limiteAulas: 2, usadas: 1)));
    await tester.pumpAndSettle();

    expect(find.text('resta 1'), findsOneWidget);
  });

  testWidgets('limite esgotado avisa, em vez de mostrar zero', (tester) async {
    await tester.pumpWidget(app(await semear(limiteAulas: 2, usadas: 2)));
    await tester.pumpAndSettle();

    expect(find.text('sem sessões'), findsOneWidget);
  });

  testWidgets('um serviço ILIMITADO não ocupa uma linha', (tester) async {
    // Uma linha a dizer "ilimitado" por cada serviço sem limite empurra
    // para baixo a única que tem informação.
    await tester.pumpWidget(app(await semear(limiteAulas: 3)));
    await tester.pumpAndSettle();

    expect(find.text('Aulas de grupo'), findsOneWidget);
    expect(find.text('Hyrox'), findsNothing);
  });

  testWidgets('sem nenhum limite, o cartão inteiro desaparece', (tester) async {
    // Um cartão "Esta semana" vazio é pior do que nenhum: lê-se como
    // um erro de carregamento.
    final firestore = await semear(limiteAulas: 3);
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('plans')
        .doc('plan_1')
        .collection('services')
        .doc('svc_aulas')
        .set({
      'enabled': true,
      'usage': {'type': 'unlimited'},
    });

    await tester.pumpWidget(app(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Esta semana'), findsNothing);
  });
}
