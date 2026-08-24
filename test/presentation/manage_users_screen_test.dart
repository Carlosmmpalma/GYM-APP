import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/presentation/screens/manage_users_screen.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

// `staffRepositoryProvider` exige um `FirebaseFunctions` no construtor
// mesmo que este ecrã só leia do Firestore; sem override, o provider
// resolveria `FirebaseFunctions.instance` real e rebentava com "No
// Firebase App" (nunca chamamos Firebase.initializeApp nos testes).
// Mesmo padrão de `book_training_screen_test.dart`.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Fase 10 — o ecrã "Utilizadores" que substitui Membros + Staff na
/// Gestão. O que se testa é o que a fusão trouxe e podia regredir sem
/// ninguém dar por isso: as duas coleções aparecerem numa lista só e
/// ordenadas em conjunto, os separadores filtrarem, e a procura.
void main() {
  Future<FakeFirebaseFirestore> seed() async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);
    final now = DateTime.now();
    final thisMonth = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';

    await tenant.collection('members').doc('member_1').set({
      'name': 'Rita Ferreira',
      'memberNumber': '000142',
      'active': true,
      'currentPaymentStatus': 'paid',
      'currentPaymentPeriod': thisMonth,
    });
    await tenant.collection('members').doc('member_2').set({
      'name': 'Beatriz Sousa',
      'memberNumber': '000201',
      'active': true,
      // Sem registo do mês corrente → em atraso (Fase 9).
      'currentPaymentStatus': 'overdue',
      'currentPaymentPeriod': thisMonth,
    });
    await tenant.collection('staff').doc('staff_1').set({
      'name': 'João Martins',
      'email': 'joao@studio.pt',
      'roles': ['instructor'],
      'active': true,
      'modalityIds': ['mod_hyrox'],
    });
    await tenant.collection('modalities').doc('mod_hyrox').set({
      'name': 'Hyrox',
      'active': true,
      'serviceIds': <String>[],
    });

    return firestore;
  }

  Widget buildApp(FakeFirebaseFirestore firestore) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const ManageUsersScreen(),
      ),
    );
  }

  testWidgets('alunos e staff aparecem na MESMA lista, ordenados em conjunto',
      (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.text('Beatriz Sousa'), findsOneWidget);
    expect(find.text('João Martins'), findsOneWidget);

    // Ordem alfabética sobre a lista fundida — não "todos os alunos e
    // depois todo o staff", que é o que sair de dois streams separados
    // daria de graça.
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) =>
            d == 'Rita Ferreira' || d == 'Beatriz Sousa' || d == 'João Martins')
        .toList();
    expect(names, ['Beatriz Sousa', 'João Martins', 'Rita Ferreira']);

    // O mockup mostra o papel/nº e o estado em cada linha.
    expect(find.text('Aluno · Nº 000142'), findsOneWidget);
    expect(find.text('Instrutor · modalidade: Hyrox'), findsOneWidget);
    expect(find.text('Em atraso'), findsOneWidget);
  });

  testWidgets('no separador "Alunos" a ordem é por número de sócio',
      (tester) async {
    // Reportado a testar em produção: a lista de alunos vinha por nome.
    // O número de sócio é a identidade que o estúdio usa ao balcão, e a
    // ordem alfabética escondia-a — além de fazer "Aluno 10" aparecer
    // antes de "Aluno 2" quando os nomes acabam em número.
    //
    // O seed serve de propósito: por nome é Beatriz (000201) antes de
    // Rita (000142); por número é ao contrário.
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alunos'));
    await tester.pumpAndSettle();

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'Rita Ferreira' || d == 'Beatriz Sousa')
        .toList();
    expect(names, ['Rita Ferreira', 'Beatriz Sousa']);
  });

  testWidgets('separador "Staff" esconde os alunos e vice-versa',
      (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();

    expect(find.text('João Martins'), findsOneWidget);
    expect(find.text('Rita Ferreira'), findsNothing);

    await tester.tap(find.text('Alunos'));
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.text('João Martins'), findsNothing);
  });

  testWidgets('procura funciona por nome e por nº de sócio', (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'martins');
    await tester.pumpAndSettle();

    expect(find.text('João Martins'), findsOneWidget);
    expect(find.text('Rita Ferreira'), findsNothing);

    await tester.enterText(find.byType(TextField), '000201');
    await tester.pumpAndSettle();

    expect(find.text('Beatriz Sousa'), findsOneWidget);
    expect(find.text('João Martins'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Ninguém encontrado'), findsOneWidget);
  });

  testWidgets('sem ninguém criado, explica o que é e oferece criar',
      (tester) async {
    await tester.pumpWidget(buildApp(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    expect(find.text('Ainda não há utilizadores'), findsOneWidget);
    expect(find.text('Criar o primeiro utilizador'), findsOneWidget);
  });
}
