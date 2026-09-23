import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/booking_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
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
///
/// Fase 10 — o ecrã passou de "um dropdown de plano por submissão" para
/// o picker agrupado do mockup, e os testes acompanharam: o que se testa
/// agora é a seleção múltipla, a exclusividade por grupo, e o relato
/// honesto de sucessos/falhas quando são várias chamadas.
class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository({this.failOnPlanId});

  /// Falha só para UM plano — para testar o caso de várias atribuições
  /// em que umas passam e outras não.
  final String? failOnPlanId;

  final _controller = StreamController<List<Subscription>>.broadcast();
  final List<Subscription> _subscriptions = [];
  final List<String> createdPlanIds = [];

  List<String> activePlanIdsFor(String memberId) => _subscriptions
      .where((s) =>
          s.memberId == memberId && s.status == SubscriptionStatus.active)
      .map((s) => s.planId)
      .toList();
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
    if (failOnPlanId == planId) {
      throw Exception('falha simulada');
    }
    createdPlanIds.add(planId);
    // Um plano ativo por membro: atribuir um novo cancela o anterior,
    // como `createSubscription.ts` faz numa escrita atómica.
    for (var i = 0; i < _subscriptions.length; i++) {
      final s = _subscriptions[i];
      if (s.memberId == memberId && s.status == SubscriptionStatus.active) {
        _subscriptions[i] = Subscription(
          id: s.id,
          memberId: s.memberId,
          planId: s.planId,
          status: SubscriptionStatus.cancelled,
          startDate: s.startDate,
          agreedPrice: s.agreedPrice,
          currency: s.currency,
          activeServiceIds: s.activeServiceIds,
        );
      }
    }
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

  @override
  Stream<Set<String>> watchEligibleMemberIdsForServices(
    Set<String> serviceIds,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> updateSubscriptionStatus({
    required String subscriptionId,
    required SubscriptionStatus status,
  }) async {}
}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  /// Semeia membro + serviços + planos. `maisPlanos` acrescenta dois,
  /// para provar que a lista é uma só e que todos são escolhíveis.
  Future<FakeFirebaseFirestore> seedFirestore({
    bool maisPlanos = false,
  }) async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);

    await tenant.collection('members').doc('member_1').set(
        {'memberNumber': 'M001', 'name': 'Ana Membro', 'status': 'active'});

    await tenant
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aula de Grupo', 'active': true});

    await tenant.collection('plans').doc('plan_1').set({
      'name': 'Plano Standard',
      'description': '',
      'currentPrice': 30,
      'currency': 'EUR',
      'active': true,
    });

    if (maisPlanos) {
      await tenant.collection('services').doc('service_sala').set({
        'name': 'Treino de sala',
        'active': true,
      });
      for (final level in [
        ('plan_plus', 'Sala Plus'),
        ('plan_premium', 'Sala Premium')
      ]) {
        await tenant.collection('plans').doc(level.$1).set({
          'name': level.$2,
          'description': '',
          'currentPrice': 50,
          'currency': 'EUR',
          'active': true,
        });
        await tenant
            .collection('plans')
            .doc(level.$1)
            .collection('services')
            .doc('service_sala')
            .set({
          'enabled': true,
          'usage': {'type': 'unlimited'}
        });
      }
    }

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
        // Fase 11 — `FirebasePlanRepository` passou a precisar de
        // Functions (`syncPlanSubscriptions`, para propagar alterações
        // ao plano a quem já o tem). Sem este override, o construtor
        // tenta `FirebaseFunctions.instanceFor` e rebenta com "No
        // Firebase App" — o ecrã ficava em erro e os finders não
        // encontravam nada. Um mock nunca invocado chega: nenhum destes
        // testes exercita a sincronização.
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        subscriptionRepositoryProvider
            .overrideWithValue(subscriptionRepository),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const AssignSubscriptionScreen(),
      ),
    );
  }

  /// Como a app o abre a sério: empilhado por cima da ficha do membro,
  /// pelo botão flutuante de `MemberDetailScreen`, e já com o membro
  /// escolhido.
  Widget buildAppDaFicha(
    FakeFirebaseFirestore firestore,
    _FakeSubscriptionRepository subscriptionRepository,
    MemberSummary membro,
  ) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        subscriptionRepositoryProvider
            .overrideWithValue(subscriptionRepository),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AssignSubscriptionScreen(initialMember: membro),
                  ),
                ),
                child: const Text('ficha do membro'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // O picker agrupado é alto (membro + o que já tem + grupos + os
  // combináveis +
  // preços + botão) e não cabe nos 800x600 do viewport de teste: um
  // `tap()` num alvo fora do ecrã não falha, simplesmente não acerta em
  // nada — e o teste passava/falhava por posição em vez de por
  // comportamento. Mesma solução de `create_series_screen_test.dart`.
  void setLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Fase 11 — o dropdown deu lugar a uma folha pesquisável
  /// (`MemberPickerField`): abre-se pelo campo e escolhe-se na lista.
  Future<void> pickMember(WidgetTester tester) async {
    await tester.tap(find.text('Escolher membro'));
    await tester.pumpAndSettle();
    // Na folha, o nome e o número são linhas separadas do `ListTile`.
    await tester.tap(find.text('Ana Membro').last);
    await tester.pumpAndSettle();
  }

  testWidgets('sem membro escolhido, explica que é o primeiro passo',
      (tester) async {
    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(), _FakeSubscriptionRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Escolhe um membro'), findsOneWidget);
  });

  testWidgets('escolher um plano e guardar atribui-o', (tester) async {
    final repository = _FakeSubscriptionRepository();
    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(await seedFirestore(), repository));
    await tester.pumpAndSettle();
    await pickMember(tester);

    expect(find.text('Nenhum plano ativo.'), findsOneWidget);

    await tester.tap(find.text('Plano Standard'));
    await tester.pumpAndSettle();

    // O campo de preço só aparece depois de escolher, pré-preenchido
    // com o preço de tabela (agreedPrice vs currentPrice).
    expect(find.text('30.00'), findsOneWidget);

    await tester.tap(find.text('Atribuir plano'));
    await tester.pumpAndSettle();

    expect(repository.createdPlanIds, ['plan_1']);
  });

  testWidgets('a lista não tem secções nem vocabulário interno',
      (tester) async {
    // O ecrã partia-se em duas secções — "níveis" em escolha única e
    // "avulsos" em escolha múltipla — sem nunca dizer porquê, e um
    // plano caía numa ou na outra consoante os serviços que
    // embrulhasse. Com um plano por membro é uma lista só.
    //
    // "Avulso" era ainda um falso amigo: a app usa "sessão avulsa"
    // noutro ecrã com o sentido normal (uma aula pontual fora da série
    // semanal).
    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(
        await seedFirestore(maisPlanos: true), _FakeSubscriptionRepository()));
    await tester.pumpAndSettle();
    await pickMember(tester);

    expect(find.textContaining('avulso'), findsNothing);
    expect(find.textContaining('Nível'), findsNothing);
    expect(find.textContaining('Grupo'), findsNothing);
    expect(find.text('ESCOLHE O PLANO'), findsOneWidget);
    // Os três planos numa lista só, todos escolhíveis.
    expect(find.byType(RadioListTile<String?>), findsNWidgets(3));
  });

  testWidgets('guardar sem escolher nada diz o que falta', (tester) async {
    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(), _FakeSubscriptionRepository()));
    await tester.pumpAndSettle();
    await pickMember(tester);

    await tester.tap(find.text('Atribuir plano'));
    await tester.pumpAndSettle();

    expect(find.text('Escolhe um plano para atribuir.'), findsOneWidget);
  });

  testWidgets('o plano em vigor aparece marcado, e o botão diz "mudar"',
      (tester) async {
    final repository = _FakeSubscriptionRepository();
    await repository.createSubscription(
      memberId: 'member_1',
      planId: 'plan_1',
      agreedPrice: 30,
      currency: 'EUR',
    );

    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(maisPlanos: true), repository));
    await tester.pumpAndSettle();
    await pickMember(tester);

    expect(find.text('atual'), findsOneWidget);
    expect(find.text('MUDAR PARA'), findsOneWidget);
    expect(find.text('Mudar de plano'), findsOneWidget);
    expect(
      find.textContaining('escolher outro substitui o atual'),
      findsOneWidget,
    );
  });

  testWidgets('mudar de plano cancela o anterior', (tester) async {
    // O servidor faz isto numa escrita atómica (ver
    // `createSubscription.ts`); aqui prova-se que o ecrã pede a coisa
    // certa e mostra o resultado certo.
    final repository = _FakeSubscriptionRepository();
    await repository.createSubscription(
      memberId: 'member_1',
      planId: 'plan_1',
      agreedPrice: 30,
      currency: 'EUR',
    );

    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(maisPlanos: true), repository));
    await tester.pumpAndSettle();
    await pickMember(tester);

    await tester.tap(find.text('Sala Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mudar de plano'));
    await tester.pumpAndSettle();

    expect(repository.createdPlanIds, ['plan_1', 'plan_plus']);
    expect(repository.activePlanIdsFor('member_1'), ['plan_plus']);
  });

  testWidgets('vindo da ficha do membro, guardar fecha o ecrã', (tester) async {
    // Ficava aberto em modo de formulário depois de guardar. Com as
    // secções antigas isso era pior: a parte que a pessoa tinha acabado
    // de usar colapsava e outra tomava-lhe o lugar — indistinguível de
    // ter sido levada para outro ecrã a pedir mais qualquer coisa.
    final repository = _FakeSubscriptionRepository();
    setLargeSurface(tester);
    await tester.pumpWidget(buildAppDaFicha(
      await seedFirestore(),
      repository,
      const MemberSummary(
        uid: 'member_1',
        memberNumber: '000142',
        name: 'Maria Madalena Gonçalves',
        active: true,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ficha do membro'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plano Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atribuir plano'));
    await tester.pumpAndSettle();

    expect(repository.createdPlanIds, ['plan_1']);
    expect(find.text('ficha do membro'), findsOneWidget);
    expect(find.textContaining('Plano: Plano Standard'), findsOneWidget);
  });

  testWidgets('uma recusa do servidor aparece no ecrã', (tester) async {
    final repository = _FakeSubscriptionRepository(failOnPlanId: 'plan_1');
    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(await seedFirestore(), repository));
    await tester.pumpAndSettle();
    await pickMember(tester);

    await tester.tap(find.text('Plano Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atribuir plano'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Não foi possível atribuir o plano'),
      findsOneWidget,
    );
  });
}
