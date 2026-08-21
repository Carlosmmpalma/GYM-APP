import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/presentation/screens/manage_members_screen.dart';

const _tenantId = 'tenant_test';

/// Fase 11 — pesquisa e filtros na lista de membros.
///
/// Com centenas de inscritos, uma lista corrida obriga a rolar à procura
/// de um nome que já se sabe. O que interessa provar aqui é o
/// comportamento que se perde numa reescrita distraída: a pesquisa sem
/// acentos, e a diferença entre "não há resultados" e "a lista está
/// vazia".
void main() {
  Future<FakeFirebaseFirestore> seed() async {
    final firestore = FakeFirebaseFirestore();
    final members =
        firestore.collection('tenants').doc(_tenantId).collection('members');

    await members.doc('m1').set({
      'memberNumber': '000001',
      'name': 'João Pedro',
      'status': 'active',
    });
    await members.doc('m2').set({
      'memberNumber': '000142',
      'name': 'Rita Ferreira',
      'status': 'active',
    });
    await members.doc('m3').set({
      'memberNumber': '000007',
      'name': 'Carlos Antigo',
      'status': 'inactive',
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
      ],
      child: const MaterialApp(home: ManageMembersScreen()),
    );
  }

  testWidgets('lista todos e conta ativos e inativos nos filtros',
      (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    expect(find.text('João Pedro'), findsOneWidget);
    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.text('Carlos Antigo'), findsOneWidget);

    // A contagem em cada chip evita o filtro que abre vazio.
    expect(find.text('Todos (3)'), findsOneWidget);
    expect(find.text('Ativos (2)'), findsOneWidget);
    expect(find.text('Inativos (1)'), findsOneWidget);
  });

  testWidgets('procura por nome ignorando acentos', (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    // "joao" tem de encontrar o "João" — quem procura não escreve os
    // acentos, quem se inscreveu escreveu-os.
    await tester.enterText(find.byType(TextField), 'joao');
    await tester.pumpAndSettle();

    expect(find.text('João Pedro'), findsOneWidget);
    expect(find.text('Rita Ferreira'), findsNothing);
  });

  testWidgets('procura também pelo nº de sócio', (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '142');
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.text('João Pedro'), findsNothing);
  });

  testWidgets('filtrar por inativos mostra só esses', (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inativos (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Carlos Antigo'), findsOneWidget);
    expect(find.text('Rita Ferreira'), findsNothing);
  });

  testWidgets('sem resultados diz que é a pesquisa, não que não há membros',
      (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    // Distinto do estado vazio de "ainda não há membros": aqui há, mas
    // nenhum corresponde. Mandar criar o primeiro seria enganador.
    expect(find.text('Nada encontrado'), findsOneWidget);
    expect(find.textContaining('"zzz"'), findsOneWidget);
    expect(find.text('Ainda não há membros'), findsNothing);
  });

  testWidgets('limpar a pesquisa devolve a lista toda', (tester) async {
    await tester.pumpWidget(buildApp(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'joao');
    await tester.pumpAndSettle();
    expect(find.text('Rita Ferreira'), findsNothing);

    await tester.tap(find.byTooltip('Limpar'));
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.text('João Pedro'), findsOneWidget);
  });
}
