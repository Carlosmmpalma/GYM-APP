import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/core/config/environment.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_ping_repository.dart';
import 'package:gym_saas/presentation/screens/hello_world_screen.dart';

/// Testa o ecrã ponta a ponta (Presentation → Application → Repositories)
/// substituindo só a fronteira de infraestrutura (firestoreProvider) por
/// um Firestore fake — não real, não emulador. Prova que a árvore de
/// providers está corretamente ligada (Fase 0), sem depender de rede.
void main() {
  testWidgets('escrever + ler mostra o último ping no ecrã',
      (WidgetTester tester) async {
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider
              .overrideWithValue(EnvironmentConfig.development),
          firestoreProvider.overrideWithValue(fakeFirestore),
          pingRepositoryProvider
              .overrideWithValue(FirebasePingRepository(fakeFirestore)),
        ],
        child: const MaterialApp(home: HelloWorldScreen()),
      ),
    );

    expect(find.text('Escrever + ler no Firestore'), findsOneWidget);

    await tester.tap(find.text('Escrever + ler no Firestore'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Último ping:'), findsOneWidget);
  });
}
