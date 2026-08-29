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
import 'package:gym_saas/domain/entities/session_occurrence.dart';
import 'package:gym_saas/presentation/screens/occurrence_detail_screen.dart';
import 'package:gym_saas/repositories/session_occurrence_repository.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gym_saas/application/providers/plan_providers.dart';
import 'package:gym_saas/repositories/catalogue_admin_repository.dart';

const _tenantId = 'tenant_test';
const _occurrenceId = 'occ_1';

/// Nenhum caminho exercitado aqui chama de facto uma Cloud Function —
/// `bookingRepositoryProvider` exige `FirebaseFunctions` no construtor
/// na mesma (`watchBookingsForOccurrence` só toca Firestore). Mesmo
/// padrão de `book_training_screen_test.dart`.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

SessionOccurrence _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return SessionOccurrence(
    id: doc.id,
    serviceId: data['serviceId'] as String,
    startAt: (data['startAt'] as Timestamp).toDate(),
    endAt: (data['endAt'] as Timestamp).toDate(),
    capacity: (data['capacity'] as num).toInt(),
    status: (data['status'] as String? ?? 'scheduled') == 'scheduled'
        ? SessionOccurrenceStatus.scheduled
        : SessionOccurrenceStatus.cancelled,
    activeBookingCount: (data['activeBookingCount'] as num? ?? 0).toInt(),
    seriesId: data['seriesId'] as String?,
    instructorId: data['instructorId'] as String?,
    modalityId: data['modalityId'] as String?,
  );
}

/// "Reduzir vagas" (UC18) passa pela Cloud Function
/// `removeMembersFromOccurrence` (Admin SDK, cascata de usage — ver
/// `removeMembersFromOccurrence.ts`). Mockar
/// `FirebaseFunctions.httpsCallable(...).call(...)` com mocktail
/// exigiria confirmar a forma exata de `HttpsCallableResult` sem correr
/// Flutter a sério (mesmo risco já documentado no README para outros
/// ecrãs) — em vez disso, este fake simula diretamente no
/// `FakeFirebaseFirestore` o que a Cloud Function faria: cancela os
/// bookings escolhidos, decrementa `activeBookingCount`, atualiza
/// `capacity`. O ecrã só precisa de reagir a sucesso/erro, não de
/// validar a lógica de negócio da função em si.
class _FakeCatalogueAdminRepository implements CatalogueAdminRepository {
  ({CatalogueKind kind, String id})? lastDelete;

  @override
  Future<void> delete({
    required CatalogueKind kind,
    required String id,
  }) async {
    lastDelete = (kind: kind, id: id);
  }
}

class _FakeSessionOccurrenceRepository implements SessionOccurrenceRepository {
  _FakeSessionOccurrenceRepository(this._firestore, this._tenantId);

  FakeFirebaseFirestore get firestoreForTest => _firestore;

  final FakeFirebaseFirestore _firestore;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> get _occurrenceDoc => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionOccurrences')
      .doc(_occurrenceId);

  @override
  Stream<SessionOccurrence?> watchOccurrence(String occurrenceId) {
    return _firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(occurrenceId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? _fromDoc(snapshot) : null);
  }

  @override
  Future<List<String>> removeMembers({
    required String occurrenceId,
    required List<String> memberIds,
    int? newCapacity,
  }) async {
    final occurrenceRef = _occurrenceDoc;
    final snap = await occurrenceRef.get();
    var activeCount = (snap.data()?['activeBookingCount'] as num? ?? 0).toInt();

    for (final memberId in memberIds) {
      final bookingRef = occurrenceRef.collection('bookings').doc(memberId);
      final bookingSnap = await bookingRef.get();
      if (bookingSnap.data()?['status'] != 'booked') continue;
      await bookingRef.update({'status': 'cancelled'});
      activeCount = activeCount > 0 ? activeCount - 1 : 0;
    }

    final update = <String, dynamic>{'activeBookingCount': activeCount};
    if (newCapacity != null) update['capacity'] = newCapacity;
    await occurrenceRef.update(update);
    return memberIds;
  }

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrences(String serviceId) =>
      const Stream.empty();

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrencesAllServices() =>
      const Stream.empty();

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrencesForServices(
    Set<String> serviceIds, {
    int? weeksAhead,
  }) =>
      const Stream.empty();

  @override
  Future<SessionOccurrence?> getOccurrence(String occurrenceId) async => null;

  @override
  Future<String> createOccurrence({
    required String serviceId,
    String? instructorId,
    String? modalityId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateOccurrence({
    required String occurrenceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
    String? instructorId,
    String? modalityId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> cancelOccurrence(String occurrenceId) =>
      throw UnimplementedError();

  @override
  Stream<List<SessionOccurrence>> watchOccurrencesForSeries(String seriesId) =>
      const Stream.empty();

  @override
  Stream<List<SessionOccurrence>> watchOccurrencesStartingBetween(
    DateTime from,
    DateTime to,
  ) =>
      const Stream.empty();

  @override
  Future<Map<String, bool>> assignMembers({
    required String occurrenceId,
    required List<String> memberIds,
    bool isExtra = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> rescheduleBooking({
    required String fromOccurrenceId,
    required String toOccurrenceId,
    required String memberId,
  }) =>
      throw UnimplementedError();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> seedFirestore({required int capacity}) async {
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
        .doc(_occurrenceId)
        .set({
      'serviceId': 'service_1',
      'startAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
      'endAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1, hours: 1))),
      'capacity': capacity,
      'status': 'scheduled',
      'activeBookingCount': 2,
    });

    for (final memberId in ['member_1', 'member_2']) {
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(memberId)
          .set({'name': 'Membro $memberId', 'status': 'active'});

      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(_occurrenceId)
          .collection('bookings')
          .doc(memberId)
          .set({
        'memberId': memberId,
        'status': 'booked',
        'source': 'self',
        'isExtra': false,
        'serviceId': 'service_1',
        'createdAt': Timestamp.now(),
      });
    }

    return firestore;
  }

  /// A mesma aula, mas sem ninguém marcado — o caso "criei por
  /// engano".
  Future<FakeFirebaseFirestore> seedEmptyOccurrence({String? seriesId}) async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(_occurrenceId)
        .set({
      'serviceId': 'service_1',
      'seriesId': seriesId,
      'startAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
      'endAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1, hours: 1))),
      'capacity': 6,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });
    return firestore;
  }

  Widget buildAppInternal(
    FakeFirebaseFirestore firestore,
    _FakeSessionOccurrenceRepository repository, {
    CatalogueAdminRepository? catalogueAdmin,
  }) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        sessionOccurrenceRepositoryProvider.overrideWithValue(repository),
        if (catalogueAdmin != null)
          catalogueAdminRepositoryProvider.overrideWithValue(catalogueAdmin),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
              uid: 'staff_1',
              tenantId: _tenantId,
              roles: {Role.manager},
            ),
          ),
        ),
      ],
      // `currentAppUserProvider` já está sempre resolvido por esta altura
      // na app real (AuthGate/HomeScreen lêem-no primeiro) — este
      // `Consumer` reproduz isso, para `_record()` (que faz `ref.read`,
      // não `ref.watch`) não apanhar o provider ainda em `AsyncLoading`
      // logo no primeiro toque.
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(currentAppUserProvider);
            return const OccurrenceDetailScreen(occurrenceId: _occurrenceId);
          },
        ),
      ),
    );
  }

  /// Variante que recebe o repositório já construído, para os testes
  /// que precisam de inspecionar o que ele registou.
  Widget buildAppWith(
    _FakeSessionOccurrenceRepository repository, {
    CatalogueAdminRepository? catalogueAdmin,
  }) =>
      buildAppInternal(repository.firestoreForTest, repository,
          catalogueAdmin: catalogueAdmin);

  Widget buildApp(FakeFirebaseFirestore firestore) => buildAppInternal(
      firestore, _FakeSessionOccurrenceRepository(firestore, _tenantId));

  testWidgets('mostra os inscritos e regista presença', (tester) async {
    final firestore = await seedFirestore(capacity: 3);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Membro member_1'), findsOneWidget);
    expect(find.text('Membro member_2'), findsOneWidget);

    expect(find.byTooltip('Presente'), findsNWidgets(2));
    // A lista de inscritos ficou abaixo da dobra quando o ecrã ganhou o
    // botão de treinar com a turma.
    await tester.ensureVisible(find.byTooltip('Presente').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Presente').first);
    await tester.pumpAndSettle();

    final attendanceDoc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(_occurrenceId)
        .collection('attendance')
        .doc('member_1')
        .get();
    expect(attendanceDoc.data()?['status'], 'attended');
    expect(attendanceDoc.data()?['recordedBy'], 'staff_1');
  });

  // Auditoria da Fase 11 — registar presença era um toque por pessoa.
  // Numa aula de vinte são vinte toques, todos os dias, e é por isso
  // que na prática ninguém as regista — deixando o painel de retenção
  // (que se alimenta delas) a mostrar toda a gente "em risco".
  testWidgets('marca a turma toda de uma vez', (tester) async {
    final firestore = await seedFirestore(capacity: 3);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcar todos como presentes'));
    await tester.pumpAndSettle();

    final attendance = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(_occurrenceId)
        .collection('attendance')
        .get();
    expect(attendance.docs.length, 2);
    expect(
      attendance.docs.every((d) => d.data()['status'] == 'attended'),
      isTrue,
    );
    expect(find.text('Presenças registadas para todos.'), findsOneWidget);
  });

  testWidgets('não sobrescreve quem já foi marcado como falta', (tester) async {
    // O caso normal do instrutor é "vieram todos menos aquele": marca a
    // falta e carrega no botão para o resto. Apagar-lhe essa marcação
    // seria apagar-lhe o trabalho.
    final firestore = await seedFirestore(capacity: 3);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Faltou').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Faltou').first);
    await tester.pumpAndSettle();

    expect(find.text('Marcar os restantes 1 como presentes'), findsOneWidget);
    await tester.tap(find.text('Marcar os restantes 1 como presentes'));
    await tester.pumpAndSettle();

    final attendance = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(_occurrenceId)
        .collection('attendance')
        .get();
    final statuses = attendance.docs
        .map((d) => d.data()['status'] as String)
        .toList()
      ..sort();
    expect(statuses, ['attended', 'no_show']);
  });

  testWidgets(
      'reduzir vagas cancela o membro escolhido e atualiza capacidade/contagem',
      (tester) async {
    final firestore = await seedFirestore(capacity: 3);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reduzir vagas'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1');
    await tester.pumpAndSettle();

    // A nova capacidade (1) obriga a escolher exatamente 1 dos 2
    // inscritos ativos para sair.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    final occurrenceDoc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(_occurrenceId)
        .get();
    expect(occurrenceDoc.data()?['capacity'], 1);
    expect(occurrenceDoc.data()?['activeBookingCount'], 1);
  });
  testWidgets('com inscritos, a única saída é cancelar', (tester) async {
    await tester.pumpWidget(buildApp(await seedFirestore(capacity: 6)));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar sessão'), findsOneWidget);
    // Eliminar deixaria marcações por libertar e utilizações por
    // devolver — a cascata que só o cancelamento faz.
    expect(find.text('Eliminar sessão'), findsNothing);
  });

  testWidgets('aula avulsa e vazia oferece eliminar em vez de cancelar',
      (tester) async {
    // Cancelar uma aula que nunca chegou a existir deixava-a no
    // calendário para sempre a dizer "cancelada" — ruído permanente por
    // causa de um engano de dois minutos.
    final catalogue = _FakeCatalogueAdminRepository();
    final repository = _FakeSessionOccurrenceRepository(
      await seedEmptyOccurrence(),
      _tenantId,
    );
    await tester.pumpWidget(
      buildAppWith(repository, catalogueAdmin: catalogue),
    );
    await tester.pumpAndSettle();

    expect(find.text('Eliminar sessão'), findsOneWidget);
    expect(find.text('Cancelar sessão'), findsNothing);

    await tester.tap(find.text('Eliminar sessão'));
    await tester.pumpAndSettle();

    // Confirmação primeiro, sempre.
    expect(find.textContaining('Eliminar'), findsWidgets);
    expect(catalogue.lastDelete, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(catalogue.lastDelete?.kind, CatalogueKind.occurrence);
    expect(catalogue.lastDelete?.id, _occurrenceId);
  });

  testWidgets('aula gerada por série NÃO oferece eliminar, mesmo vazia',
      (tester) async {
    // As aulas de série têm id determinístico (`{seriesId}_{data}`) e o
    // cron da noite recria-as com o mesmo id. Um botão "eliminar" ali
    // seria um botão que se desfaz sozinho — e que faria reaparecer as
    // marcações antigas agarradas à aula nova.
    final repository = _FakeSessionOccurrenceRepository(
      await seedEmptyOccurrence(seriesId: 'series_1'),
      _tenantId,
    );
    await tester.pumpWidget(buildAppWith(repository));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar sessão'), findsNothing);
    expect(find.text('Cancelar sessão'), findsOneWidget);
  });
}
