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
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_booking_repository.dart';
import 'package:gym_saas/presentation/screens/my_bookings_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Auditoria da Fase 11 — três bugs em "as minhas marcações", todos com
/// a mesma raiz: a marcação não guardava a data da sessão, e o ecrã não
/// sabia distinguir uma aula de um treino livre.
///
/// As marcações de treino livre vivem noutro caminho
/// (`freeTrainingSchedules/{week}/slots/{slot}/bookings`) mas são
/// apanhadas pela mesma collection group query. O ecrã tratava-as como
/// aulas: mostrava "Sessão já não disponível" e o botão "Cancelar"
/// chamava a Cloud Function das aulas, falhando sempre.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  late FakeFirebaseFirestore firestore;

  DocumentReference<Map<String, dynamic>> tenant() =>
      firestore.collection('tenants').doc(_tenantId);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await tenant().collection('services').doc('service_aulas').set({
      'name': 'Aula de Grupo',
      'active': true,
    });
    await tenant().collection('services').doc('service_livre').set({
      'name': 'Treino Livre',
      'active': true,
    });
  });

  Future<void> addSessionBooking({
    required String occurrenceId,
    required DateTime startAt,
  }) async {
    final occurrence =
        tenant().collection('sessionOccurrences').doc(occurrenceId);
    await occurrence.set({
      'serviceId': 'service_aulas',
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(startAt.add(const Duration(hours: 1))),
      'capacity': 10,
      'status': 'scheduled',
      'activeBookingCount': 1,
    });
    await occurrence.collection('bookings').doc(_memberId).set({
      'memberId': _memberId,
      'status': 'booked',
      'source': 'self',
      'isExtra': false,
      'serviceId': 'service_aulas',
      'startAt': Timestamp.fromDate(startAt),
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  }

  Future<void> addFreeTrainingBooking({
    required String weekId,
    required String slotId,
    required DateTime startAt,
  }) async {
    await tenant()
        .collection('freeTrainingSchedules')
        .doc(weekId)
        .collection('slots')
        .doc(slotId)
        .collection('bookings')
        .doc(_memberId)
        .set({
      'memberId': _memberId,
      'status': 'booked',
      'source': 'self',
      'isExtra': false,
      'serviceId': 'service_livre',
      'startAt': Timestamp.fromDate(startAt),
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  }

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        // O repositório REAL sobre um Firestore falso: o que se quer
        // provar aqui é precisamente o mapeamento do caminho para o
        // tipo de marcação, que um fake de repositório esconderia.
        bookingRepositoryProvider.overrideWith(
          (ref) => FirebaseBookingRepository(
            firestore,
            _MockFirebaseFunctions(),
            _tenantId,
          ),
        ),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
                uid: _memberId, tenantId: _tenantId, roles: {Role.member}),
          ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: MyBookingsScreen())),
    );
  }

  testWidgets('uma marcação de treino livre é identificada como tal',
      (tester) async {
    await addFreeTrainingBooking(
      weekId: '2026-W40',
      slotId: 'slot_1',
      startAt: DateTime.now().add(const Duration(days: 1)),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Treino livre'), findsOneWidget);
    // O sintoma antigo: sem saber que era treino livre, o ecrã tentava
    // ler uma ocorrência que não existe.
    expect(find.text('Sessão já não disponível'), findsNothing);
  });

  testWidgets('as marcações são ordenadas pela data da SESSÃO', (tester) async {
    // A de amanhã foi marcada depois da do mês que vem: por data de
    // criação apareceria em último.
    await addSessionBooking(
      occurrenceId: 'occ_longe',
      startAt: DateTime.now().add(const Duration(days: 30)),
    );
    await addFreeTrainingBooking(
      weekId: '2026-W40',
      slotId: 'slot_amanha',
      startAt: DateTime.now().add(const Duration(days: 1)),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final livre = tester.getTopLeft(find.text('Treino livre')).dy;
    final aula = tester.getTopLeft(find.text('Aula de Grupo')).dy;
    expect(livre, lessThan(aula));
  });

  testWidgets('sessões passadas saem das próximas e perdem o "Cancelar"',
      (tester) async {
    await addSessionBooking(
      occurrenceId: 'occ_passada',
      startAt: DateTime.now().subtract(const Duration(days: 3)),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('JÁ REALIZADAS'), findsOneWidget);
    expect(find.text('Realizada'), findsOneWidget);
    // Cancelar uma sessão que já aconteceu não devolve vaga nenhuma, e
    // a Cloud Function recusaria de qualquer forma.
    expect(find.text('Cancelar'), findsNothing);
    expect(
        find.text('Não tens nenhuma sessão futura marcada.'), findsOneWidget);
  });

  testWidgets('uma sessão futura mantém o "Cancelar"', (tester) async {
    await addSessionBooking(
      occurrenceId: 'occ_futura',
      startAt: DateTime.now().add(const Duration(days: 2)),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('JÁ REALIZADAS'), findsNothing);
  });
}
