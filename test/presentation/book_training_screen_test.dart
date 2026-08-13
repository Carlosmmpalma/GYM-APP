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
    return false;
  }

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) => const Stream.empty();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> seedFirestore({
    required int capacity,
    bool memberIsEligible = true,
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
      'startAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
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
        'activeServiceIds': ['service_1'],
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
    const appUser = AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    expect(find.text('1 vaga(s) de 1'), findsOneWidget);
    expect(find.text('Marcar'), findsOneWidget);

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    expect(find.text('Sem vagas'), findsWidgets);
  });

  testWidgets(
      'bloqueia a marcação com mensagem própria quando o membro não é elegível',
      (tester) async {
    final firestore = await seedFirestore(capacity: 1, memberIsEligible: false);
    const appUser = AppUser(uid: 'member_1', tenantId: _tenantId, roles: {Role.member});

    await tester.pumpWidget(buildApp(firestore, appUser));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não tens um plano ativo que dê acesso a este serviço.'),
      findsOneWidget,
    );
    // A ocorrência continua com a vaga livre — o bloqueio acontece antes
    // de sequer tentar a transação de booking.
    expect(find.text('1 vaga(s) de 1'), findsOneWidget);
  });
}
