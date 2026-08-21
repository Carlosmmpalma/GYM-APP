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
  _FakeSubscriptionRepository({this.conflictException, this.failOnPlanId});

  /// Se não for `null`, toda chamada a [createSubscription] falha com
  /// esta exceção — simula o que `createSubscription.ts` faria ao
  /// encontrar um conflito (Domain Model v1 §15).
  final SubscriptionServiceConflictException? conflictException;

  /// Falha só para UM plano — para testar o caso de várias atribuições
  /// em que umas passam e outras não.
  final String? failOnPlanId;

  final _controller = StreamController<List<Subscription>>.broadcast();
  final List<Subscription> _subscriptions = [];
  final List<String> createdPlanIds = [];
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
    if (failOnPlanId == planId) {
      throw Exception('falha simulada');
    }
    createdPlanIds.add(planId);
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
  Future<void> updateSubscriptionStatus({
    required String subscriptionId,
    required SubscriptionStatus status,
  }) async {}
}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  /// Semeia membro + serviços + planos. `salaLevels` cria dois planos
  /// ligados a um serviço com `exclusiveGroup: 'sala'` — é o que faz o
  /// ecrã desenhar um grupo de seleção única em vez de checkboxes.
  Future<FakeFirebaseFirestore> seedFirestore({
    bool salaLevels = false,
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

    if (salaLevels) {
      await tenant.collection('services').doc('service_sala').set({
        'name': 'Treino de sala',
        'active': true,
        'exclusiveGroup': 'sala',
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

  // O picker agrupado é alto (membro + o que já tem + grupos + avulsos +
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
      buildApp(await seedFirestore(), _FakeSubscriptionRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Escolhe um membro'), findsOneWidget);
  });

  testWidgets('atribui um plano avulso e reflete-o no que o membro já tem',
      (tester) async {
    final repository = _FakeSubscriptionRepository();
    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(await seedFirestore(), repository));
    await tester.pumpAndSettle();

    await pickMember(tester);

    expect(find.text('Nenhum plano ativo.'), findsOneWidget);
    // Sem `exclusiveGroup` em nenhum serviço, o plano é avulso →
    // checkbox, não radio.
    expect(find.byType(CheckboxListTile), findsOneWidget);

    await tester.tap(find.text('Plano Standard'));
    await tester.pumpAndSettle();

    // O campo de preço só aparece depois de escolher, pré-preenchido com
    // o preço de tabela (agreedPrice vs currentPrice).
    expect(find.text('30.00'), findsOneWidget);
    expect(find.text('Guardar 1 plano(s)'), findsOneWidget);

    await tester.tap(find.text('Guardar 1 plano(s)'));
    await tester.pumpAndSettle();

    expect(repository.createdPlanIds, ['plan_1']);
    expect(find.textContaining('Atribuído: Plano Standard'), findsOneWidget);
    // A seleção do que ficou feito é limpa; o card de topo já mostra o
    // plano novo.
    expect(find.text('· Plano Standard (Aula de Grupo)'), findsOneWidget);
  });

  testWidgets('níveis do mesmo grupo são seleção única (UC26 atualizado)',
      (tester) async {
    final repository = _FakeSubscriptionRepository();
    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(salaLevels: true), repository));
    await tester.pumpAndSettle();

    await pickMember(tester);

    expect(find.textContaining('NÍVEL DE SALA'), findsOneWidget);
    expect(find.text('Nenhum'), findsOneWidget);

    await tester.tap(find.text('Sala Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala Premium'));
    await tester.pumpAndSettle();

    // O segundo toque SUBSTITUI o primeiro — é isto que a exclusividade
    // significa, e é o que antes só se descobria com um erro da Cloud
    // Function depois de submeter.
    expect(find.text('Guardar 1 plano(s)'), findsOneWidget);

    await tester.tap(find.text('Guardar 1 plano(s)'));
    await tester.pumpAndSettle();

    expect(repository.createdPlanIds, ['plan_premium']);
  });

  testWidgets('grupo já ocupado fica bloqueado e diz o que fazer',
      (tester) async {
    final repository = _FakeSubscriptionRepository();
    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(salaLevels: true), repository));
    await tester.pumpAndSettle();

    await pickMember(tester);
    await tester.tap(find.text('Sala Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar 1 plano(s)'));
    await tester.pumpAndSettle();

    // Com o nível já atribuído, o grupo deixa de oferecer opções.
    expect(find.textContaining('Os níveis deste grupo não se acumulam'),
        findsOneWidget);
    expect(find.text('Sala Premium'), findsNothing);
  });

  testWidgets(
      'mostra a mensagem de conflito quando a Cloud Function recusa por serviço já coberto',
      (tester) async {
    final repository = _FakeSubscriptionRepository(
      conflictException:
          const SubscriptionServiceConflictException(['Aula de Grupo']),
    );
    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(await seedFirestore(), repository));
    await tester.pumpAndSettle();

    await pickMember(tester);
    await tester.tap(find.text('Plano Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar 1 plano(s)'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Este membro já tem acesso a: Aula de Grupo'),
      findsOneWidget,
    );
  });

  testWidgets(
      'com várias atribuições, diz o que passou E o que falhou (não é atómico)',
      (tester) async {
    final repository = _FakeSubscriptionRepository(failOnPlanId: 'plan_1');
    setLargeSurface(tester);
    await tester.pumpWidget(
        buildApp(await seedFirestore(salaLevels: true), repository));
    await tester.pumpAndSettle();

    await pickMember(tester);
    await tester.tap(find.text('Sala Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plano Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar 2 plano(s)'));
    await tester.pumpAndSettle();

    // Um passou, o outro não — e o ecrã diz as duas coisas em vez de
    // fingir tudo-ou-nada.
    expect(repository.createdPlanIds, ['plan_plus']);
    expect(find.textContaining('Atribuído: Sala Plus'), findsOneWidget);
    expect(find.textContaining('Plano Standard:'), findsOneWidget);
  });
}
