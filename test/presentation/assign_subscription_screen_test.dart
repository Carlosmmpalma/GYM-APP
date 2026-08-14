import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/booking_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/plan.dart';
import 'package:gym_saas/domain/entities/subscription.dart';
import 'package:gym_saas/presentation/screens/assign_subscription_screen.dart';
import 'package:gym_saas/repositories/subscription_repository.dart';

const _tenantId = 'tenant_test';

/// Fase 3 — em falta desde então (ver README, "Ainda em aberto" da
/// Fase 3): evitámos escrever este teste porque `createSubscription`
/// passou logo de início a Cloud Function (Admin SDK), e mockar a
/// cadeia `FirebaseFunctions.httpsCallable(...).call(...)` com mocktail
/// exigiria confirmar a forma exata de `HttpsCallable`/
/// `HttpsCallableResult` sem correr Flutter a sério.
///
/// Entretanto a Fase 4 provou um padrão melhor (`book_training_screen_test.dart`,
/// `my_bookings_screen_test.dart`): um fake que implementa o repository
/// inteiro e é injetado via `overrideWithValue`, em vez de mockar
/// `cloud_functions` diretamente. Aqui isso é ainda mais simples do que
/// nos testes de booking — nem precisamos de mexer no
/// `FakeFirebaseFirestore` diretamente, só de manter a lista de
/// subscriptions em memória, porque este ecrã só lê subscriptions
/// através do repository (nunca diretamente do Firestore).
class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository({this.conflictException});

  /// Se não for `null`, toda chamada a [createSubscription] falha com
  /// esta exceção — simula o que `createSubscription.ts` faria ao
  /// encontrar um conflito (Domain Model v1 §15).
  final SubscriptionServiceConflictException? conflictException;

  final _controller = StreamController<List<Subscription>>.broadcast();
  final List<Subscription> _subscriptions = [];
  int _nextId = 1;

  void _emit() => _controller.add(List.unmodifiable(_subscriptions));

  @override
  Stream<List<Subscription>> watchMemberSubscriptions(String memberId) async* {
    yield _subscriptions.where((s) => s.memberId == memberId).toList();
    yield* _controller.stream
        .map((all) => all.where((s) => s.memberId == memberId).toList());
  }

  @override
  Future<void> createSubscription({
    required String memberId,
    required String planId,
    required double agreedPrice,
    required String currency,
  }) async {
    if (conflictException != null) throw conflictException!;
    _subscriptions.add(Subscription(
      id: 'sub_${_nextId++}',
      memberId: memberId,
      planId: planId,
      status: SubscriptionStatus.active,
      startDate: DateTime.now(),
      agreedPrice: agreedPrice,
      currency: currency,
      activeServiceIds: const {'service_1'},
    ));
    _emit();
  }

  @override
  Future<bool> isEligibleForService({
    required String memberId,
    required String serviceId,
  }) async =>
      throw UnimplementedError('Não usado neste ecrã.');

  @override
  Future<String?> getGrantingPlanId({
    required String memberId,
    required String serviceId,
  }) async =>
      null;

  @override
  Stream<Set<String>> watchEligibleMemberIds(String serviceId) =>
      const Stream.empty();
}

void main() {
  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc('member_1')
        .set(
            {'memberNumber': 'M001', 'name': 'Ana Membro', 'status': 'active'});
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
    return firestore;
  }

  Widget buildApp(
    FakeFirebaseFirestore firestore,
    _FakeSubscriptionRepository subscriptionRepository,
  ) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        subscriptionRepositoryProvider
            .overrideWithValue(subscriptionRepository),
      ],
      child:
          const MaterialApp(home: Scaffold(body: AssignSubscriptionScreen())),
    );
  }

  Future<void> selectDropdown(
    WidgetTester tester, {
    required Finder dropdownFinder,
    required String optionText,
  }) async {
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionText).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'atribui um plano com sucesso, mostra-o em "Planos ativos" e limpa o formulário',
      (tester) async {
    final firestore = await seedFirestore();
    final repository = _FakeSubscriptionRepository();

    await tester.pumpWidget(buildApp(firestore, repository));
    await tester.pumpAndSettle();

    await selectDropdown(
      tester,
      dropdownFinder: find.byType(DropdownButtonFormField<MemberSummary>),
      optionText: 'Ana Membro (M001)',
    );

    expect(
      find.text('Este membro não tem nenhum plano ativo neste momento.'),
      findsOneWidget,
    );

    await selectDropdown(
      tester,
      dropdownFinder: find.byType(DropdownButtonFormField<Plan>),
      optionText: 'Plano Standard',
    );

    // Preço pré-preenchido com o currentPrice do Plan (ver nota na
    // classe sobre agreedPrice vs currentPrice).
    expect(find.text('30.00'), findsOneWidget);

    await tester.tap(find.text('Atribuir'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Plano atribuído com sucesso'),
      findsOneWidget,
    );
    // Fica no mesmo membro (pedido depois da Fase 3, task #49) — a
    // secção de planos ativos já reflete a nova subscription.
    expect(find.textContaining('Plano Standard'), findsWidgets);
    // Preço limpo, pronto para atribuir o próximo plano ao mesmo membro.
    expect(find.text('30.00'), findsNothing);
  });

  testWidgets(
      'mostra a mensagem de conflito quando a Cloud Function recusa por serviço já coberto',
      (tester) async {
    final firestore = await seedFirestore();
    final repository = _FakeSubscriptionRepository(
      conflictException:
          const SubscriptionServiceConflictException(['Aula de Grupo']),
    );

    await tester.pumpWidget(buildApp(firestore, repository));
    await tester.pumpAndSettle();

    await selectDropdown(
      tester,
      dropdownFinder: find.byType(DropdownButtonFormField<MemberSummary>),
      optionText: 'Ana Membro (M001)',
    );
    await selectDropdown(
      tester,
      dropdownFinder: find.byType(DropdownButtonFormField<Plan>),
      optionText: 'Plano Standard',
    );

    await tester.tap(find.text('Atribuir'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Este membro já tem acesso a: Aula de Grupo através de outra '
        'subscription ativa.',
      ),
      findsOneWidget,
    );
  });
}
