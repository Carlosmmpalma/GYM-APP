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
import 'package:gym_saas/domain/entities/service.dart';
import 'package:gym_saas/domain/entities/session_occurrence.dart';
import 'package:gym_saas/presentation/screens/create_series_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

/// Nenhum caminho exercitado aqui chega a submeter o formulário
/// (`_submit` chamaria `sessionSeriesRepositoryProvider`/
/// `sessionOccurrenceRepositoryProvider`, Cloud Functions reais) — só
/// o aviso de conflito, que é puramente client-side (lê
/// `seriesProvider`/`allUpcomingOccurrencesProvider`, ambos Firestore
/// puro). Mesma justificação de `manage_series_screen_test.dart`.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  // O formulário tem muitos campos — maior que o viewport de teste por
  // omissão (800x600), o que deixava `_TimeConflictBanner` fora da
  // área "visível" da sliver list do `ListView` e, por vezes (sob
  // carga, a correr a suite toda), `scrollUntilVisible` falhava com
  // "Bad state: No element" a meio do scroll. Um viewport maior do que
  // o conteúdo evita ter de scrollar de todo — mais simples e estável
  // do que lidar com scroll assíncrono num `ListView` lazy.
  void setLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// [upcomingOccurrences] substitui `allUpcomingOccurrencesProvider`
  /// quando fornecido. Esse provider filtra por `startAt >= now` no
  /// Firestore — semear uma ocorrência "hoje às 18:00" tornaria o teste
  /// dependente da hora a que a suite corre (passava de manhã, falhava
  /// a partir das 18:00). Substituir o provider isola o que este teste
  /// realmente quer verificar: a lógica de sobreposição do aviso de
  /// conflito, não o filtro temporal da query (esse é comportamento do
  /// repository, coberto noutro sítio).
  Widget buildApp(
    FakeFirebaseFirestore firestore, {
    List<SessionOccurrence>? upcomingOccurrences,
  }) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        if (upcomingOccurrences != null)
          allUpcomingOccurrencesProvider
              .overrideWith((ref) => Stream.value(upcomingOccurrences)),
      ],
      child: const MaterialApp(home: CreateSeriesScreen()),
    );
  }

  Future<FakeFirebaseFirestore> seedBase() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Hyrox', 'active': true});
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('staff')
        .doc('instructor_1')
        .set({
      'name': 'Rita',
      'roles': ['instructor'],
      'status': 'active'
    });
    return firestore;
  }

  Future<void> pickService(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<Service>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hyrox').last);
    await tester.pumpAndSettle();
  }

  Future<void> pickInstructor(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rita').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Fase 8 (auditoria funcional) — série recorrente com o mesmo instrutor/dia/hora '
      'de outra série ativa mostra o aviso de conflito', (tester) async {
    final firestore = await seedBase();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionSeries')
        .doc('series_existing')
        .set({
      'serviceId': 'service_1',
      'instructorId': 'instructor_1',
      'dayOfWeek': DateTime.monday,
      'startTime': '18:00',
      'durationMinutes': 60,
      'capacity': 6,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 5)),
      'preAssignedMemberIds': <String>[],
      'status': 'active',
    });

    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    // Defaults do ecrã já são "Semanal, fixa" + segunda-feira + 18:00
    // + 60 minutos — exatamente a série semeada, por isso basta
    // escolher serviço/instrutor para expor o conflito sem interagir
    // com os pickers de data/hora.
    await pickService(tester);
    expect(find.textContaining('Conflito de horário'), findsNothing);

    await pickInstructor(tester);
    expect(find.textContaining('Conflito de horário'), findsOneWidget);
    expect(find.textContaining('Segunda 18:00'), findsOneWidget);
  });

  testWidgets(
      'Fase 8 (auditoria funcional) — sem instrutor escolhido não há aviso de conflito',
      (tester) async {
    final firestore = await seedBase();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionSeries')
        .doc('series_existing')
        .set({
      'serviceId': 'service_1',
      'instructorId': 'instructor_1',
      'dayOfWeek': DateTime.monday,
      'startTime': '18:00',
      'durationMinutes': 60,
      'capacity': 6,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 5)),
      'preAssignedMemberIds': <String>[],
      'status': 'active',
    });

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();
    await pickService(tester);

    expect(find.textContaining('Conflito de horário'), findsNothing);
  });

  testWidgets(
      'Fase 8 (auditoria funcional) — "só esta data" compara contra ocorrências '
      'já materializadas do mesmo instrutor, no mesmo dia', (tester) async {
    final firestore = await seedBase();
    // Os defaults do ecrã para "só esta data" são hoje + 18:00 + 60
    // minutos — a ocorrência substituída no provider coincide
    // exatamente com isso.
    final now = DateTime.now();
    final occurrence = SessionOccurrence(
      id: 'occ_today',
      serviceId: 'service_1',
      instructorId: 'instructor_1',
      startAt: DateTime(now.year, now.month, now.day, 18, 0),
      endAt: DateTime(now.year, now.month, now.day, 19, 0),
      capacity: 6,
      status: SessionOccurrenceStatus.scheduled,
      activeBookingCount: 0,
    );

    setLargeSurface(tester);
    await tester
        .pumpWidget(buildApp(firestore, upcomingOccurrences: [occurrence]));
    await tester.pumpAndSettle();

    await pickService(tester);
    await tester.tap(find.text('Só esta data'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conflito de horário'), findsNothing);

    await pickInstructor(tester);
    expect(find.textContaining('Conflito de horário'), findsOneWidget);
  });
}
