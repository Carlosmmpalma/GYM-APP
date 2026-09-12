import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/presentation/widgets/today_classes.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

/// O repositório de ocorrências recebe `FirebaseFunctions` no
/// construtor (usa-as para atribuir membros). Sem este override ele
/// nunca chega a ser construído, o provider fica em erro, e a lista
/// aparece VAZIA — que é indistinguível de "não há aulas hoje".
class _FakeFunctions extends Mock implements FirebaseFunctions {}

/// A lista de aulas de hoje, no início do Instrutor e no painel do
/// Gestor.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Future<FakeFirebaseFirestore> semear() async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    await tenant.collection('services').doc('service_1').set({
      'name': 'Treino Funcional',
      'active': true,
    });

    Future<void> aula(
      String id,
      DateTime inicio, {
      required String instructorId,
      int inscritos = 2,
    }) async {
      await tenant.collection('sessionOccurrences').doc(id).set({
        'serviceId': 'service_1',
        'instructorId': instructorId,
        'startAt': Timestamp.fromDate(inicio),
        'endAt': Timestamp.fromDate(inicio.add(const Duration(hours: 1))),
        'capacity': 10,
        'status': 'scheduled',
        'activeBookingCount': inscritos,
      });
    }

    // Às 07:00 e às 23:00 de hoje: uma já aconteceu (salvo se o teste
    // correr de madrugada), a outra ainda não. As duas TÊM de aparecer.
    await aula('occ_manha', hoje.add(const Duration(hours: 7)),
        instructorId: 'instructor_1');
    await aula('occ_noite', hoje.add(const Duration(hours: 23)),
        instructorId: 'instructor_1');
    // De outro instrutor, hoje.
    await aula('occ_outro', hoje.add(const Duration(hours: 10)),
        instructorId: 'instructor_2');

    return firestore;
  }

  Widget app(FakeFirebaseFirestore firestore, {String? instructorId}) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_FakeFunctions()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListView(
            children: [TodayClasses(instructorId: instructorId)],
          ),
        ),
      ),
    );
  }

  testWidgets('uma aula que JÁ aconteceu hoje continua na lista',
      (tester) async {
    // É o caso todo. O `upcomingWeekOccurrencesProvider` começa em
    // `DateTime.now()`, por isso a aula das 7h desaparecia da lista às
    // 7h01 — exatamente quando passava a precisar de chamada. A janela
    // desta lista é a semana ISO inteira, de propósito.
    final firestore = await semear();
    await tester.pumpWidget(app(firestore, instructorId: 'instructor_1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('07:00'), findsOneWidget);
    expect(find.textContaining('23:00'), findsOneWidget);
  });

  testWidgets('o crachá só aparece depois de a aula começar', (tester) async {
    // A das 07:00 já aconteceu e ninguém foi marcado — tem aviso. A das
    // 23:00 tem toda a gente por marcar também, e isso é o estado
    // NORMAL de uma aula que ainda não começou: um aviso aceso desde a
    // manhã para a aula da noite ensina a ignorar os avisos.
    final firestore = await semear();
    await tester.pumpWidget(app(firestore, instructorId: 'instructor_1'));
    await tester.pumpAndSettle();

    expect(find.text('2 por marcar'), findsOneWidget);
  });

  testWidgets('com instrutor, só mostra as aulas dele', (tester) async {
    final firestore = await semear();
    await tester.pumpWidget(app(firestore, instructorId: 'instructor_1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10:00'), findsNothing);
  });

  testWidgets('sem instrutor (Gestor), mostra as do estúdio todo',
      (tester) async {
    // A pergunta do Gestor é "alguma chamada por fazer no estúdio?",
    // não "nas minhas aulas" — ele não tem aulas.
    final firestore = await semear();
    await tester.pumpWidget(app(firestore));
    await tester.pumpAndSettle();

    expect(find.textContaining('07:00'), findsOneWidget);
    expect(find.textContaining('10:00'), findsOneWidget);
    expect(find.textContaining('23:00'), findsOneWidget);
  });

  testWidgets('num dia sem aulas não deixa um título vazio', (tester) async {
    // Sem isto, o painel do Gestor abria com um "Hoje" seguido de nada
    // — que se lê como um erro de carregamento, não como um dia livre.
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(app(firestore));
    await tester.pumpAndSettle();

    // `SectionLabel` escreve o título em maiúsculas.
    expect(find.text('HOJE'), findsNothing);
    expect(find.textContaining('inscritos'), findsNothing);
  });
}
