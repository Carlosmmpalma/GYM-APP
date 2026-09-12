import 'dart:async';

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
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/book_training_screen.dart';
import 'package:gym_saas/repositories/booking_repository.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

// Fase 3: subscriptionRepositoryProvider depende de functionsProvider
// mesmo que os métodos usados aqui (isEligibleForService/
// getGrantingPlanId) só toquem no Firestore — o construtor de
// FirebaseSubscriptionRepository exige-o na mesma, e
// FirebaseFunctions.instance real lançaria "no Firebase App" nestes
// testes (nunca chamamos Firebase.initializeApp aqui). Um mock nunca
// invocado chega.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

// Fase 4 — createBooking passou de transação Firestore client-side
// (Fase 2) para Cloud Function (Admin SDK, ver createBooking.ts).
// Mockar a cadeia `FirebaseFunctions.httpsCallable(...).call(...)` com
// mocktail exigiria confirmar a forma exata de `HttpsCallable`/
// `HttpsCallableResult` sem correr Flutter a sério — o mesmo risco já
// documentado no README para AssignSubscriptionScreen/ManagerScreen.
// Em vez disso, este fake simula, diretamente no `FakeFirebaseFirestore`
// do teste, exatamente o que `createBooking.ts`/`cancelBooking.ts`
// fariam ao Firestore (criar booking + (des)incrementar
// activeBookingCount) — este ecrã só precisa de reagir corretamente a
// sucesso/erro, não de validar a lógica de negócio da Cloud Function em
// si (isso pertence a testes TS contra o emulador de Functions, ainda
// não montados neste projeto — ver README, "Ainda em aberto" da Fase 4).
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository(this._firestore, this._tenantId);

  final FakeFirebaseFirestore _firestore;
  final String _tenantId;

  // Fase 10 — `watchMyBookings` era `Stream.empty()`: bastava porque
  // nenhum ecrã testado aqui olhava para as marcações do próprio membro.
  // Deixou de bastar quando "Marcar treino" passou a esconder o botão nas
  // sessões já marcadas — com um stream vazio, o ecrã nunca sabia de
  // nenhuma marcação e o teste passaria por a funcionalidade não existir.
  final _mine = <Booking>[];
  final _mineController = StreamController<List<Booking>>.broadcast();

  void _emitMine() => _mineController.add(List.unmodifiable(_mine));

  DocumentReference<Map<String, dynamic>> _occurrenceDoc(String occurrenceId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(occurrenceId);

  @override
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    final occurrenceRef = _occurrenceDoc(occurrenceId);
    final bookingRef = occurrenceRef.collection('bookings').doc(memberId);

    final occurrenceSnap = await occurrenceRef.get();
    if (!occurrenceSnap.exists) throw const SessionNotBookableException();
    final data = occurrenceSnap.data()!;
    final capacity = (data['capacity'] as num).toInt();
    final activeCount = (data['activeBookingCount'] as num? ?? 0).toInt();

    final bookingSnap = await bookingRef.get();
    if (bookingSnap.exists && bookingSnap.data()?['status'] == 'booked') {
      throw const AlreadyBookedException();
    }
    if (activeCount >= capacity) {
      throw const BookingCapacityExceededException();
    }

    await bookingRef.set({
      'memberId': memberId,
      'status': 'booked',
      'source': 'self',
      'isExtra': false,
      'serviceId': data['serviceId'],
      'createdAt': Timestamp.now(),
    });
    await occurrenceRef.update({'activeBookingCount': activeCount + 1});

    _mine
      ..removeWhere((b) => b.occurrenceId == occurrenceId)
      ..add(Booking(
        id: memberId,
        occurrenceId: occurrenceId,
        memberId: memberId,
        status: BookingStatus.booked,
        source: BookingSource.self,
        isExtra: false,
        createdAt: DateTime.now(),
        serviceId: data['serviceId'] as String?,
      ));
    _emitMine();
  }

  @override
  Future<bool> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    final occurrenceRef = _occurrenceDoc(occurrenceId);
    final bookingRef = occurrenceRef.collection('bookings').doc(memberId);

    final bookingSnap = await bookingRef.get();
    if (!bookingSnap.exists || bookingSnap.data()?['status'] != 'booked') {
      throw const BookingNotFoundException();
    }
    final occurrenceSnap = await occurrenceRef.get();
    final activeCount =
        (occurrenceSnap.data()?['activeBookingCount'] as num? ?? 0).toInt();

    await bookingRef.update({'status': 'cancelled'});
    await occurrenceRef.update({
      'activeBookingCount': activeCount > 0 ? activeCount - 1 : 0,
    });
    _mine.removeWhere((b) => b.occurrenceId == occurrenceId);
    _emitMine();
    return false;
  }

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) async* {
    yield _mine.where((b) => b.memberId == memberId).toList();
    yield* _mineController.stream
        .map((all) => all.where((b) => b.memberId == memberId).toList());
  }

  @override
  Stream<List<Booking>> watchBookingsForOccurrence(String occurrenceId) =>
      const Stream.empty();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  /// [grantedServiceIds] — os serviços a que o plano do membro dá
  /// acesso. Desde a Fase 11 o ecrã só mostra sessões destes, por isso
  /// um teste que semeie um serviço extra tem de o incluir aqui; caso
  /// contrário está a testar o filtro, não o que julga estar a testar.
  Future<FakeFirebaseFirestore> seedFirestore({
    required int capacity,
    bool memberIsEligible = true,
    List<String> grantedServiceIds = const ['service_1'],
  }) async {
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
      'startAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
      'endAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1, hours: 1))),
      'capacity': capacity,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });

    // Fase 3 — UC06/07/08/09: só marca quem tem uma subscription ativa
    // que dá acesso a este serviço.
    if (memberIsEligible) {
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
        'agreedPrice': 50,
        'currency': 'EUR',
        'activeServiceIds': grantedServiceIds,
      });
    }

    return firestore;
  }

  Widget buildApp(FakeFirebaseFirestore firestore, AppUser appUser) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        bookingRepositoryProvider.overrideWithValue(
          _FakeBookingRepository(firestore, _tenantId),
        ),
        currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
      ],
      child: const MaterialApp(home: Scaffold(body: BookTrainingScreen())),
    );
  }

  testWidgets('mostra a sessão com vagas e permite marcar quando elegível',
      (tester) async {
    final firestore = await seedFirestore(capacity: 1);
    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    // Fase 5: mostra o nome do serviço em cada cartão — sem isto não
    // dava para perceber que treino era, com várias sessões possíveis
    // de serviços diferentes na mesma lista (bug reportado).
    expect(find.text('Aula de Grupo'), findsOneWidget);
    expect(find.text('1/1 vagas'), findsOneWidget);
    expect(find.text('Marcar'), findsOneWidget);

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    // Fase 10 — para QUEM marcou, o cartão passa a dizer que já está
    // marcado; "Sem vagas" (capacidade esgotada) é o que os OUTROS
    // membros veriam.
    expect(find.text('Marcado'), findsOneWidget);
    expect(find.text('Marcar'), findsNothing);
  });

  testWidgets('sem plano que dê acesso, a sessão nem sequer aparece (Fase 11)',
      (tester) async {
    // Este teste verificava que tocar em "Marcar" devolvia
    // `NotEligibleForServiceException` com mensagem própria. Desde a
    // Fase 11 o ecrã não chega lá: filtra as sessões pelos serviços a
    // que o plano dá acesso, e uma porta fechada não se mostra. É uma
    // garantia mais forte do que a anterior.
    //
    // A mensagem de erro continua a ser precisa (a Cloud Function é a
    // única validação que conta, e o plano pode ser cancelado com o
    // ecrã aberto) e continua coberta em
    // `test/application/book_session_use_case_test.dart`.
    final firestore = await seedFirestore(capacity: 1, memberIsEligible: false);
    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('Marcar'), findsNothing);
    expect(find.text('Aula de Grupo'), findsNothing);
    expect(find.text('O teu plano não dá acesso a aulas'), findsOneWidget);
  });

  testWidgets(
      'mostra sessões de TODOS os serviços, não só do primeiro (bug corrigido)',
      (tester) async {
    // Até à Fase 5, `primaryServiceProvider` só mostrava o "primeiro
    // serviço ativo" — uma segunda série num serviço diferente ficava
    // invisível, sem nenhum aviso. Este teste prova a correção.
    final firestore = await seedFirestore(
      capacity: 1,
      grantedServiceIds: const ['service_1', 'service_2'],
    );
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_2')
        .set({'name': 'Pilates', 'active': true});
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_2')
        .set({
      'serviceId': 'service_2',
      'startAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 2))),
      'endAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 2, hours: 1))),
      'capacity': 4,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });

    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});
    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('Aula de Grupo'), findsOneWidget);
    expect(find.text('Pilates'), findsOneWidget);
  });

  testWidgets(
      'Fase 10 — separadores por modalidade filtram e só aparecem quando há modalidades',
      (tester) async {
    final firestore = await seedFirestore(
      capacity: 5,
      grantedServiceIds: const ['service_1', 'service_2'],
    );

    // Duas modalidades, ambas com sessões futuras: aparecem as duas
    // como separador. Uma terceira SEM sessões nenhumas não aparece —
    // um separador que abre vazio é pior do que não existir.
    for (final m in [
      ('mod_pilates', 'Pilates'),
      ('mod_hyrox', 'Hyrox'),
      ('mod_vazia', 'Sem sessões'),
    ]) {
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('modalities')
          .doc(m.$1)
          .set({
        'name': m.$2,
        'active': true,
        'serviceIds': ['service_1']
      });
    }

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_2')
        .set({'name': 'Hyrox Class', 'active': true});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_1')
        .update({'modalityId': 'mod_pilates'});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_2')
        .set({
      'serviceId': 'service_2',
      'modalityId': 'mod_hyrox',
      'startAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 2))),
      'endAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 2, hours: 1))),
      'capacity': 5,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });

    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});
    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('Pilates'), findsOneWidget);
    expect(find.text('Hyrox'), findsOneWidget);
    expect(find.text('Sem sessões'), findsNothing);

    // "Todas" mostra o horário completo.
    expect(find.text('Aula de Grupo'), findsOneWidget);
    expect(find.text('Hyrox Class'), findsOneWidget);

    await tester.tap(find.text('Hyrox'));
    await tester.pumpAndSettle();

    expect(find.text('Hyrox Class'), findsOneWidget);
    expect(find.text('Aula de Grupo'), findsNothing);
  });

  testWidgets('sem modalidades definidas não mostra separadores nenhuns',
      (tester) async {
    final firestore = await seedFirestore(capacity: 1);
    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('Todas'), findsNothing);
    expect(find.text('Aula de Grupo'), findsOneWidget);
  });

  testWidgets(
      'sessão já marcada não oferece "Marcar" — mostra que está marcada',
      (tester) async {
    final firestore = await seedFirestore(capacity: 5);
    const appUser =
        AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('Marcar'), findsOneWidget);

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    // Bug reportado: o botão continuava lá depois de marcar, e a única
    // resposta a premi-lo outra vez era o erro `AlreadyBookedException`
    // vindo da Cloud Function.
    expect(find.text('Marcar'), findsNothing);
    expect(find.text('Marcado'), findsOneWidget);
    expect(
      find.textContaining('Já tens esta sessão marcada'),
      findsOneWidget,
    );
  });

  group('só o que o plano dá (Fase 11)', () {
    /// Semeia DUAS aulas de serviços diferentes e um plano que só dá
    /// acesso a uma delas.
    Future<FakeFirebaseFirestore> seedTwoServices() async {
      final firestore = FakeFirebaseFirestore();
      final tenant = firestore.collection('tenants').doc(_tenantId);

      await tenant
          .collection('services')
          .doc('service_1')
          .set({'name': 'Aula de Grupo', 'active': true});
      await tenant
          .collection('services')
          .doc('service_pilates')
          .set({'name': 'Pilates', 'active': true});

      for (final entry in [
        ('occ_grupo', 'service_1'),
        ('occ_pilates', 'service_pilates'),
      ]) {
        await tenant.collection('sessionOccurrences').doc(entry.$1).set({
          'serviceId': entry.$2,
          'startAt':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
          'endAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 1, hours: 1))),
          'capacity': 5,
          'status': 'scheduled',
          'activeBookingCount': 0,
        });
      }

      await tenant.collection('subscriptions').doc('sub_1').set({
        'memberId': 'member_1',
        'planId': 'plan_1',
        'status': 'active',
        'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'agreedPrice': 50,
        'currency': 'EUR',
        // Só Aula de Grupo. Pilates é uma venda por fazer, não uma
        // oferta.
        'activeServiceIds': ['service_1'],
      });

      return firestore;
    }

    testWidgets('serviços a que o aluno não tem direito NÃO aparecem',
        (tester) async {
      final firestore = await seedTwoServices();
      const appUser =
          AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

      await tester.pumpWidget(buildApp(firestore, appUser));
      await tester.pumpAndSettle();

      expect(find.text('Aula de Grupo'), findsOneWidget);
      // Antes desta fase, o Pilates aparecia com botão "Marcar" e só ao
      // tocar é que vinha o erro de elegibilidade da Cloud Function.
      expect(find.text('Pilates'), findsNothing);
    });

    testWidgets('sem nenhum plano ativo, explica em vez de mostrar vazio',
        (tester) async {
      final firestore = await seedTwoServices();
      // Subscrição cancelada: continua a existir, deixa de dar direito.
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('subscriptions')
          .doc('sub_1')
          .update({'status': 'cancelled'});

      const appUser =
          AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

      await tester.pumpWidget(buildApp(firestore, appUser));
      await tester.pumpAndSettle();

      expect(find.text('O teu plano não dá acesso a aulas'), findsOneWidget);
      expect(find.text('Marcar'), findsNothing);
    });

    testWidgets('com plano, mas sem aulas desse serviço, explica-o',
        (tester) async {
      final firestore = await seedTwoServices();
      // O plano passa a dar só Pilates... e apaga-se a aula de Pilates.
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('subscriptions')
          .doc('sub_1')
          .update({
        'activeServiceIds': ['service_pilates'],
      });
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc('occ_pilates')
          .delete();

      const appUser =
          AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

      await tester.pumpWidget(buildApp(firestore, appUser));
      await tester.pumpAndSettle();

      // Distinto de "não tens plano": aqui há plano, faltam é sessões.
      //
      // Deixou de haver uma terceira mensagem para "o ginásio TEM
      // aulas, mas não do teu plano": distingui-la obrigava a ler
      // também o horário a que este aluno não tem acesso — a leitura
      // que a query filtrada por serviço passou a evitar. O que ele
      // pode fazer é o mesmo nos dois casos.
      expect(find.text('Sem aulas para marcar'), findsOneWidget);
    });
  });

  // NOTA — fica aqui um buraco de teste, assumido.
  //
  // O bug de a contagem semanal ser sempre a da semana CORRENTE (e não
  // a da semana da aula) foi encontrado a usar a app a sério e
  // corrigido em `_WeeklyUsageLine`. Tentei prendê-lo com um teste aqui
  // e não consegui: neste fixture a linha de utilização nem chega a ser
  // desenhada — o `applicableUsageRuleProvider` não resolve contra o
  // `fake_cloud_firestore`, e forçá-lo dava um teste que prova mais
  // sobre o fixture do que sobre o ecrã.
  //
  // Preferi deixar o buraco escrito a deixar um teste que não testa o
  // que diz. Quem lhe mexer: o caminho é dar ao fixture uma regra de
  // utilização que o provider reconheça, e depois semear uma aula a
  // mais de sete dias — aí a etiqueta tem de dizer "Nessa semana" e o
  // aviso de limite não pode aparecer.
}
