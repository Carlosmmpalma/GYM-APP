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
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/instructor_home_screen.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';
const _instructorUid = 'instructor_1';

/// `InstructorHomeScreen` só lê Firestore (staff/membros/modalidades/
/// ocorrências) — nunca chama uma Cloud Function. O mock existe porque
/// `sessionOccurrenceRepositoryProvider` exige `FirebaseFunctions` no
/// construtor, mesmo padrão de `occurrence_detail_screen_test.dart`.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  const appUser = AppUser(
    uid: _instructorUid,
    tenantId: _tenantId,
    roles: {Role.instructor},
  );

  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: InstructorHomeScreen(appUser: appUser)),
      ),
    );
  }

  Future<FakeFirebaseFirestore> seed() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('modalities')
        .doc('mod_hyrox')
        .set({'name': 'Hyrox', 'active': true, 'serviceIds': <String>[]});
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('staff')
        .doc(_instructorUid)
        .set({
      'name': 'João Martins',
      'roles': ['instructor'],
      'status': 'active',
      'modalityIds': ['mod_hyrox'],
    });
    return firestore;
  }

  testWidgets(
      'Fase 8 — mostra nome/modalidade do instrutor e os atalhos do mockup',
      (tester) async {
    final firestore = await seed();
    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('João Martins'), findsOneWidget);
    expect(find.text('Instrutor · Hyrox'), findsOneWidget);

    expect(find.text('Alunos'), findsOneWidget);
    expect(find.text('Biblioteca de exercícios'), findsOneWidget);
    expect(find.text('As minhas aulas'), findsOneWidget);
    expect(find.text('Enviar notificação'), findsOneWidget);
  });

  testWidgets(
      'Fase 8 — "Sessões hoje" conta só as sessões DESTE instrutor, hoje',
      (tester) async {
    final firestore = await seed();
    final now = DateTime.now();
    final monday = isoWeekRange(now).start;

    Future<void> addOccurrence(
      String id, {
      required String instructorId,
      required DateTime startAt,
    }) {
      return firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(id)
          .set({
        'serviceId': 'service_1',
        'instructorId': instructorId,
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(startAt.add(const Duration(hours: 1))),
        'capacity': 6,
        'status': 'scheduled',
        'activeBookingCount': 0,
      });
    }

    final todayNoon = DateTime(now.year, now.month, now.day, 12, 0);
    await addOccurrence('mine_today',
        instructorId: _instructorUid, startAt: todayNoon);
    // Outro instrutor, hoje — não conta.
    await addOccurrence('other_today',
        instructorId: 'instructor_2', startAt: todayNoon);
    // Este instrutor, mas NOUTRO dia da mesma semana — não conta.
    // Escolhido a partir da segunda-feira da semana corrente, saltando
    // o próprio dia de hoje: fixar "segunda" fazia o teste falhar
    // sempre que a suite corresse a uma segunda-feira (hoje == segunda
    // → a ocorrência caía no mesmo dia e passava a contar).
    final otherDay = monday.day == now.day
        ? monday.add(const Duration(days: 1, hours: 12))
        : monday.add(const Duration(hours: 12));
    await addOccurrence('mine_other_day',
        instructorId: _instructorUid, startAt: otherDay);

    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc('member_1')
        .set({'name': 'Rita', 'memberNumber': '0142', 'status': 'active'});

    await tester.pumpWidget(buildApp(firestore));
    await tester.pumpAndSettle();

    expect(find.text('Sessões hoje'), findsOneWidget);
    expect(find.text('Alunos ativos'), findsOneWidget);
    // 1 sessão minha hoje, 1 aluno ativo.
    expect(find.text('1'), findsNWidgets(2));
  });
}
