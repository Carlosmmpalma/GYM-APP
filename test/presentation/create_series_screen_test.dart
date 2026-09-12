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

  /// Escolher o dia da semana conta como "o horário já é uma escolha"
  /// — é o que destranca o aviso de conflito.
  Future<void> pickDayOfWeek(WidgetTester tester, String day) async {
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(day).last);
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
    // + 60 minutos — exatamente a série semeada.
    await pickService(tester);
    expect(find.textContaining('já tem'), findsNothing);

    await pickInstructor(tester);

    // ⚠️ Reportado em produção: "aparece sempre que o instrutor já tem
    // aulas naquele horário, e ele não tem". Tinha. O que estava
    // errado era o momento — o aviso disparava aqui, a comparar com
    // segunda às 18:00, que são os valores por omissão do formulário e
    // não uma escolha de ninguém. Quem tivesse uma aula nesse horário
    // via o aviso em todas as criações seguintes, e um aviso que
    // aparece sempre deixa de ser lido.
    expect(find.textContaining('já tem'), findsNothing);

    // A partir do momento em que o horário é uma escolha, avisa.
    await pickDayOfWeek(tester, 'Segunda');
    expect(find.textContaining('já tem uma aula a esta hora'), findsOneWidget);
    // E mostra o dia inteiro, não só a colisão: é assim que o Gestor
    // escolhe uma hora livre sem sair do ecrã.
    expect(find.textContaining('O que ele já tem'), findsOneWidget);
    expect(find.textContaining('18:00–19:00'), findsOneWidget);
  });

  testWidgets('mexer no horário sem conflito real continua sem avisar',
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

    setLargeSurface(tester);
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await pickService(tester);
    await pickInstructor(tester);
    await pickDayOfWeek(tester, 'Quarta');

    expect(find.textContaining('já tem'), findsNothing);
  });

  testWidgets(
      'gravar com conflito pede confirmação em vez de criar em silêncio',
      (tester) async {
    // A outra metade do que foi reportado: "e depois cria". O aviso
    // podia nunca ter sido visto — horário nos valores por omissão, ou
    // simplesmente fora do ecrã — e a aula sobreposta nascia sem que
    // ninguém decidisse nada.
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

    await pickService(tester);
    await pickInstructor(tester);

    // Sem tocar no horário — fica em segunda/18:00, o slot ocupado.
    expect(find.textContaining('já tem'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Criar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AlertDialog, 'Conflito de horário'),
        findsOneWidget);
    expect(find.text('Criar mesmo assim'), findsOneWidget);

    // "Rever" fecha e não cria nada — o formulário fica como estava.
    await tester.tap(find.text('Rever'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    final created = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionSeries')
        .get();
    expect(created.docs.length, 1, reason: 'só a série semeada');
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

    expect(find.textContaining('já tem'), findsNothing);
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
    expect(find.textContaining('já tem'), findsNothing);

    await pickInstructor(tester);
    expect(find.textContaining('já tem uma aula a esta hora'), findsOneWidget);
  });
}
