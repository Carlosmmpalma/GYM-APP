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
import 'package:gym_saas/presentation/screens/my_bookings_screen.dart';
import 'package:gym_saas/repositories/booking_repository.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

// Fase 5 — `sessionOccurrenceRepositoryProvider` (usado por
// `occurrenceProvider`, que este ecrã já lia desde a Fase 4 para saber
// a que horas é a sessão de uma marcação) passou a exigir
// `functionsProvider` no construtor (`assignMembers`, novo nesta
// fase) — mesma justificação de `book_training_screen_test.dart`: um
// mock nunca invocado chega, o ecrã não chama nenhuma Cloud Function
// de atribuição.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

// Fase 4 — cancelBooking passou a Cloud Function (ver nota equivalente
// em book_training_screen_test.dart sobre porque um fake que mexe
// diretamente no FakeFirebaseFirestore é preferível a mockar
// `cloud_functions` aqui).
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
    throw UnimplementedError('Não usado neste ecrã.');
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
    // Booking de teste não tem serviceId/period (nunca havia nenhuma
    // UsageRule limited envolvida aqui) — nunca haveria nada para
    // devolver.
    return false;
  }

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) {
    // Mesma query da implementação real (`firebase_booking_repository.dart`)
    // — só a escrita mudou para Cloud Function na Fase 4, a leitura
    // continua direta ao Firestore.
    return _firestore
        .collectionGroup('bookings')
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              final occurrenceId = doc.reference.parent.parent!.id;
              return Booking(
                id: doc.id,
                occurrenceId: occurrenceId,
                memberId: data['memberId'] as String,
                status: (data['status'] as String) == 'booked'
                    ? BookingStatus.booked
                    : BookingStatus.cancelled,
                source: BookingSource.self,
                isExtra: data['isExtra'] as bool? ?? false,
                createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              );
            }).toList());
  }

  @override
  Stream<List<Booking>> watchBookingsForOccurrence(String occurrenceId) =>
      const Stream.empty();
}

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
          functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
          bookingRepositoryProvider.overrideWithValue(
            _FakeBookingRepository(firestore, _tenantId),
          ),
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
          functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
          bookingRepositoryProvider.overrideWithValue(
            _FakeBookingRepository(firestore, _tenantId),
          ),
          currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
        ],
        child: const MaterialApp(home: Scaffold(body: MyBookingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Fase 5: mostra o nome do serviço, não mais "Marcação #abc123" —
    // sem isto não dava para perceber que treino era (bug reportado).
    expect(find.text('Aula de Grupo'), findsOneWidget);

    // Fase 4: "Cancelar" já não cancela direto — abre um diálogo de
    // confirmação primeiro (aviso sobre a utilização, ver
    // `my_bookings_screen.dart#_confirm`). Esta marcação não tem
    // `serviceId` (não foi criada com uma UsageRule limited associada),
    // por isso o diálogo mostra a mensagem simples, sem menção a
    // utilização.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar marcação?'), findsOneWidget);
    expect(find.text('A vaga fica livre para outro membro.'), findsOneWidget);

    await tester.tap(find.text('Cancelar marcação'));
    await tester.pumpAndSettle();

    expect(find.text('Ainda não tens nenhuma marcação.'), findsOneWidget);
  });
}
