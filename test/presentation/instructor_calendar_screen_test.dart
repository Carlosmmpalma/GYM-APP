import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/utils/iso_week.dart';
import 'package:gym_saas/presentation/screens/instructor_calendar_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

/// Nenhum caminho exercitado aqui chama de facto uma Cloud Function —
/// `InstructorCalendarScreen` só lê Firestore (ocorrências/serviços/
/// modalidades/staff/treino livre), nunca escreve. Mesmo padrão de
/// `occurrence_detail_screen_test.dart`.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Widget buildApp(FakeFirebaseFirestore firestore, {String? instructorId}) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
      ],
      child: MaterialApp(
        home: InstructorCalendarScreen(instructorId: instructorId),
      ),
    );
  }

  testWidgets(
      'Fase 8 (UC20 atualizado) — tabs Seg/Ter mostram só as sessões do dia selecionado',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    final monday = isoWeekRange(now).start;
    final tuesday = monday.add(const Duration(days: 1));

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
        .doc('occ_monday')
        .set({
      'serviceId': 'service_1',
      'startAt': Timestamp.fromDate(monday.add(const Duration(hours: 12))),
      'endAt': Timestamp.fromDate(monday.add(const Duration(hours: 13))),
      'capacity': 5,
      'status': 'scheduled',
      'activeBookingCount': 2,
    });
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_tuesday')
        .set({
      'serviceId': 'service_1',
      'startAt': Timestamp.fromDate(tuesday.add(const Duration(hours: 12))),
      'endAt': Timestamp.fromDate(tuesday.add(const Duration(hours: 13))),
      'capacity': 5,
      'status': 'scheduled',
      'activeBookingCount': 1,
    });

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seg'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aula de Grupo'), findsOneWidget);
    expect(find.textContaining('2/5 inscritos'), findsOneWidget);
    expect(find.textContaining('1/5 inscritos'), findsNothing);

    await tester.tap(find.text('Ter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1/5 inscritos'), findsOneWidget);
    expect(find.textContaining('2/5 inscritos'), findsNothing);
  });

  testWidgets(
      'Fase 8 (UC20 atualizado) — treino livre publicado aparece só no dia do bloco',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    final monday = isoWeekRange(now).start;
    final weekId = weekIdForDate(now);

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('freeTrainingSchedules')
        .doc(weekId)
        .set({'weekStart': Timestamp.fromDate(monday), 'status': 'published'});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('freeTrainingSchedules')
        .doc(weekId)
        .collection('slots')
        .doc('slot_monday')
        .set({
      'serviceId': 'service_free',
      'startAt': Timestamp.fromDate(monday.add(const Duration(hours: 12))),
      'endAt': Timestamp.fromDate(monday.add(const Duration(hours: 14))),
      'capacity': 10,
      'activeBookingCount': 3,
    });

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seg'));
    await tester.pumpAndSettle();
    expect(find.text('Treino livre'), findsOneWidget);
    expect(find.textContaining('3/10 inscritos'), findsOneWidget);

    await tester.tap(find.text('Ter'));
    await tester.pumpAndSettle();
    expect(find.text('Treino livre'), findsNothing);
    expect(find.text('Sem sessões neste dia.'), findsOneWidget);
  });

  testWidgets(
      'Fase 8 (UC20) — mostra os nomes dos inscritos do dia, com "+N" acima de 3',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    final monday = isoWeekRange(now).start;

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Hyrox', 'active': true});

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_monday')
        .set({
      'serviceId': 'service_1',
      'startAt': Timestamp.fromDate(monday.add(const Duration(hours: 12))),
      'endAt': Timestamp.fromDate(monday.add(const Duration(hours: 13))),
      'capacity': 10,
      'status': 'scheduled',
      'activeBookingCount': 4,
    });

    const names = ['Rita', 'Miguel', 'Tiago', 'Ana'];
    for (var i = 0; i < names.length; i++) {
      final uid = 'member_$i';
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(uid)
          .set({'name': names[i], 'memberNumber': '000$i', 'status': 'active'});
      await firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc('occ_monday')
          .collection('bookings')
          .doc(uid)
          .set({
        'memberId': uid,
        'status': 'booked',
        'source': 'self',
        'isExtra': false,
        'serviceId': 'service_1',
        'createdAt': Timestamp.now(),
      });
    }

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seg'));
    await tester.pumpAndSettle();

    // 4 inscritos, só os 3 primeiros por nome + "+1".
    expect(find.textContaining('4/10 inscritos'), findsOneWidget);
    expect(find.textContaining('+1'), findsOneWidget);
  });

  testWidgets(
      'Fase 8 (UC20 atualizado) — um Instrutor só vê as suas próprias sessões',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    final monday = isoWeekRange(now).start;

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Aula de Grupo', 'active': true});

    // Capacidades distintas (5 vs 8) para distinguir as duas sessões nas
    // asserções sem depender do fuso horário local em que os testes
    // correm — formatar `startAt` para "HH:mm" dependeria da conversão
    // UTC→local feita por `Timestamp.toDate()`, que este teste não
    // controla.
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_mine')
        .set({
      'serviceId': 'service_1',
      'instructorId': 'instructor_a',
      'startAt': Timestamp.fromDate(monday.add(const Duration(hours: 12))),
      'endAt': Timestamp.fromDate(monday.add(const Duration(hours: 13))),
      'capacity': 5,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc('occ_other')
        .set({
      'serviceId': 'service_1',
      'instructorId': 'instructor_b',
      'startAt': Timestamp.fromDate(monday.add(const Duration(hours: 12))),
      'endAt': Timestamp.fromDate(monday.add(const Duration(hours: 13))),
      'capacity': 8,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });

    await tester.pumpWidget(buildApp(firestore, instructorId: 'instructor_a'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seg'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0/5 inscritos'), findsOneWidget);
    expect(find.textContaining('0/8 inscritos'), findsNothing);
  });
}
