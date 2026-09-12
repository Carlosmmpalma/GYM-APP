import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/observability/data_health.dart';
import 'package:gym_saas/presentation/widgets/data_health_banner.dart';

/// A rede por baixo de 54 sítios que tratam "falhou a carregar" e "está
/// vazio" como a mesma coisa.
///
/// Apanhei isto a usar a app: a cache local do Firestore ficou
/// corrompida e o instrutor viu o seu próprio ecrã com um "?" no lugar
/// do nome, "0 sessões hoje" e "0 alunos ativos". Tudo plausível, tudo
/// falso, e sem um único sinal de que algo tinha corrido mal.
void main() {
  group('DataHealthObserver', () {
    test('regista um provider que falha e esquece-o quando recupera', () {
      final observer = DataHealthObserver();
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      final falha = StateProvider<AsyncValue<int>>(
        (ref) => const AsyncValue.loading(),
      );

      // Carregar não é falhar.
      container.read(falha);
      expect(container.read(dataHealthProvider), isEmpty);

      container.read(falha.notifier).state =
          AsyncValue.error(Exception('sem rede'), StackTrace.empty);
      expect(container.read(dataHealthProvider), hasLength(1));

      // Voltar a `loading` também não é recuperar: ainda não se sabe.
      container.read(falha.notifier).state = const AsyncValue.loading();
      expect(container.read(dataHealthProvider), hasLength(1));

      container.read(falha.notifier).state = const AsyncValue.data(1);
      expect(container.read(dataHealthProvider), isEmpty);
    });

    test('duas chaves da mesma família contam separadamente', () {
      // Sem isto, `memberProfile(a)` a recuperar apagava a falha de
      // `memberProfile(b)` — e o aviso desaparecia com metade da app
      // ainda partida.
      final observer = DataHealthObserver();
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      final familia =
          StateProvider.family<AsyncValue<int>, String>((ref, chave) {
        return AsyncValue.error(Exception(chave), StackTrace.empty);
      });

      container.read(familia('a'));
      container.read(familia('b'));
      expect(container.read(dataHealthProvider), hasLength(2));

      container.read(familia('a').notifier).state = const AsyncValue.data(1);
      expect(container.read(dataHealthProvider), hasLength(1));
    });
  });

  group('DataHealthBanner', () {
    Widget host(ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DataHealthBanner(child: Scaffold(body: Text('conteúdo'))),
        ),
      );
    }

    testWidgets('sem falhas, não há aviso nenhum', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      await tester.pump(const Duration(seconds: 10));

      expect(find.textContaining('ler os teus dados'), findsNothing);
      expect(find.text('conteúdo'), findsOneWidget);
    });

    testWidgets('uma falha passageira não chega a aparecer', (tester) async {
      // Um aviso que pisca a cada hesitação da rede ensina as pessoas a
      // ignorá-lo.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      container.read(dataHealthProvider.notifier).registarFalha('x');
      await tester.pump(const Duration(seconds: 1));
      container.read(dataHealthProvider.notifier).registarRecuperacao('x');
      await tester.pump(const Duration(seconds: 10));

      expect(find.textContaining('ler os teus dados'), findsNothing);
    });

    testWidgets('uma falha que se aguenta é dita ao utilizador',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      container.read(dataHealthProvider.notifier).registarFalha('x');
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(find.textContaining('ler os teus dados'), findsOneWidget);
      // E o conteúdo continua lá: avisar não é razão para tirar a app
      // das mãos de quem a está a usar.
      expect(find.text('conteúdo'), findsOneWidget);
    });

    testWidgets('quando recupera, o aviso sai sozinho', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      container.read(dataHealthProvider.notifier).registarFalha('x');
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.textContaining('ler os teus dados'), findsOneWidget);

      container.read(dataHealthProvider.notifier).registarRecuperacao('x');
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('ler os teus dados'), findsNothing);
    });

    testWidgets('quem o dispensa não volta a ser incomodado pela mesma falha',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      container.read(dataHealthProvider.notifier).registarFalha('x');
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      await tester.tap(find.text('Ok'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));

      expect(find.textContaining('ler os teus dados'), findsNothing);
    });
  });
}
