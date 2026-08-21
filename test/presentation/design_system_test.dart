import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme/app_colors.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/domain/entities/payment_record.dart';
import 'package:gym_saas/domain/entities/subscription.dart';
import 'package:gym_saas/presentation/widgets/design_system.dart';
import 'package:gym_saas/presentation/widgets/status_pills.dart';

/// Fase 10 — os componentes do design system. Testa-se o que pode
/// regredir sem ninguém dar por isso (as iniciais do avatar, a fração da
/// barra, o mapeamento estado→cor), não a aparência em si — isso é para
/// comparar com o mockup a olho.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Center(child: child)),
      );

  group('Avatar.initialsOf', () {
    test('primeiro + último nome', () {
      expect(Avatar.initialsOf('Rita Ferreira'), 'RF');
      expect(Avatar.initialsOf('João Pedro Martins'), 'JM');
    });

    test('nome único devolve uma inicial', () {
      expect(Avatar.initialsOf('Rita'), 'R');
    });

    test('espaços a mais não geram iniciais vazias', () {
      expect(Avatar.initialsOf('  Rita   Ferreira  '), 'RF');
    });

    test('nome vazio devolve "?" em vez de rebentar', () {
      expect(Avatar.initialsOf(''), '?');
      expect(Avatar.initialsOf('   '), '?');
    });
  });

  group('Pill', () {
    testWidgets('mostra o texto e usa a cor do estado', (tester) async {
      await tester.pumpWidget(
        wrap(const Pill('Em atraso', tone: PillTone.warn)),
      );

      expect(find.text('Em atraso'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Em atraso'));
      expect(text.style?.color, AppColors.warn);
    });

    testWidgets('tone neutral usa mute, não uma cor de estado', (tester) async {
      await tester.pumpWidget(wrap(const Pill('Sem registo')));
      final text = tester.widget<Text>(find.text('Sem registo'));
      expect(text.style?.color, AppColors.mute);
    });
  });

  group('UsageBar', () {
    testWidgets('1/2 → 50%', (tester) async {
      await tester.pumpWidget(wrap(const UsageBar(used: 1, limit: 2)));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.5);
    });

    testWidgets('acima do limite satura em 100%, nunca passa', (tester) async {
      await tester.pumpWidget(wrap(const UsageBar(used: 5, limit: 2)));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
    });

    testWidgets('limite 0 não divide por zero', (tester) async {
      await tester.pumpWidget(wrap(const UsageBar(used: 0, limit: 0)));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.0);
    });
  });

  group('PillTabs', () {
    testWidgets('tocar num separador devolve o índice', (tester) async {
      var selected = -1;
      await tester.pumpWidget(
        wrap(
          PillTabs(
            labels: const ['Hyrox', 'Pilates', 'PT'],
            selectedIndex: 0,
            onSelected: (i) => selected = i,
          ),
        ),
      );

      await tester.tap(find.text('PT'));
      expect(selected, 2);
    });
  });

  group('ScreenHeader', () {
    testWidgets('título em maiúsculas + subtítulo + slash', (tester) async {
      await tester.pumpWidget(
        wrap(
            const ScreenHeader(title: 'Mensalidades', subtitle: 'Agosto 2026')),
      );

      expect(find.text('MENSALIDADES'), findsOneWidget);
      expect(find.text('Agosto 2026'), findsOneWidget);
      expect(find.byType(SlashDivider), findsOneWidget);
    });
  });

  group('AppBanner', () {
    testWidgets('mostra título e corpo', (tester) async {
      await tester.pumpWidget(
        wrap(const AppBanner(
          title: 'Conta inativa',
          text: 'Mensalidade em atraso.',
        )),
      );

      expect(find.text('Conta inativa'), findsOneWidget);
      expect(find.text('Mensalidade em atraso.'), findsOneWidget);
    });
  });

  group('tema', () {
    test('é escuro e usa o fundo do mockup', () {
      final theme = AppTheme.dark;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.void_);
      expect(theme.colorScheme.primary, AppColors.red);
    });
  });

  group('EmptyState', () {
    testWidgets('mostra título, explicação e ação', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        wrap(EmptyState(
          icon: Icons.people_outline,
          title: 'Ainda não há membros',
          message: 'Os membros são as pessoas inscritas no ginásio.',
          actionLabel: 'Criar o primeiro membro',
          onAction: () => tapped++,
        )),
      );

      expect(find.text('Ainda não há membros'), findsOneWidget);
      expect(
        find.text('Os membros são as pessoas inscritas no ginásio.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Criar o primeiro membro'));
      expect(tapped, 1);
    });

    testWidgets('sem ação, não desenha botão nenhum', (tester) async {
      await tester.pumpWidget(
        wrap(const EmptyState(
          icon: Icons.monitor_heart_outlined,
          title: 'Sem avaliações',
          message: 'Assim que o instrutor fizer a primeira, aparece aqui.',
        )),
      );

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('pré-requisito aparece como banner', (tester) async {
      await tester.pumpWidget(
        wrap(const EmptyState(
          icon: Icons.card_membership_outlined,
          title: 'Ainda não há planos',
          message: 'Um plano é o que o aluno subscreve.',
          prerequisite: 'Cria primeiro os serviços.',
        )),
      );

      expect(find.byType(AppBanner), findsOneWidget);
      expect(find.text('Cria primeiro os serviços.'), findsOneWidget);
    });
  });

  group('ErrorState', () {
    testWidgets('mostra mensagem humana e esconde o detalhe técnico',
        (tester) async {
      await tester.pumpWidget(
        wrap(const ErrorState(
          error: '[cloud_firestore/permission-denied] Null value error',
          message: 'Não foi possível carregar o treino livre.',
        )),
      );

      expect(find.text('Algo correu mal'), findsOneWidget);
      expect(
        find.text('Não foi possível carregar o treino livre.'),
        findsOneWidget,
      );

      // O ponto todo deste widget: a exceção crua NÃO é a primeira coisa
      // que o utilizador lê — foi assim que o bug do treino livre lhe
      // chegou. Continua acessível, mas só se a abrir.
      expect(find.textContaining('permission-denied'), findsNothing);

      await tester.tap(find.text('Detalhe técnico'));
      await tester.pumpAndSettle();
      expect(find.textContaining('permission-denied'), findsOneWidget);
    });

    testWidgets('sem onRetry não desenha botão de tentar outra vez',
        (tester) async {
      await tester.pumpWidget(wrap(const ErrorState(error: 'x')));
      expect(find.text('Tentar outra vez'), findsNothing);
    });

    testWidgets('onRetry é chamado ao tocar', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        wrap(ErrorState(error: 'x', onRetry: () => retries++)),
      );

      await tester.tap(find.text('Tentar outra vez'));
      expect(retries, 1);
    });

    testWidgets('compact é uma linha só, sem detalhe nem retry',
        (tester) async {
      await tester.pumpWidget(
        wrap(const ErrorState(
          error: 'boom',
          message: 'Não foi possível carregar serviços.',
          compact: true,
        )),
      );

      expect(find.text('Não foi possível carregar serviços.'), findsOneWidget);
      expect(find.text('Detalhe técnico'), findsNothing);
      expect(find.text('boom'), findsNothing);
    });
  });

  group('status pills', () {
    testWidgets('o mesmo estado lê-se igual em qualquer ecrã', (tester) async {
      // A razão de existirem: `PaymentStatus.paid` era "✓ Pago" em dois
      // ecrãs e "Em dia" num terceiro, com cores diferentes.
      expect(
        PaymentStatusPill.labelAndToneFor(PaymentStatus.paid),
        ('Pago', PillTone.ok),
      );
      expect(
        PaymentStatusPill.labelAndToneFor(PaymentStatus.paidLate),
        ('Pago com atraso', PillTone.warn),
      );
      expect(
        PaymentStatusPill.labelAndToneFor(PaymentStatus.overdue),
        ('Em atraso', PillTone.danger),
      );
      // Sem registo não é o mesmo que em atraso: o Gestor pode ainda não
      // ter lançado o mês.
      expect(
        PaymentStatusPill.labelAndToneFor(null),
        ('Sem registo', PillTone.neutral),
      );

      await tester
          .pumpWidget(wrap(const PaymentStatusPill(PaymentStatus.paid)));
      expect(find.text('Pago'), findsOneWidget);
    });

    testWidgets('subscrição cancelada e expirada são ambas neutras',
        (tester) async {
      await tester.pumpWidget(
        wrap(const Column(
          children: [
            SubscriptionStatusPill(SubscriptionStatus.cancelled),
            SubscriptionStatusPill(SubscriptionStatus.expired),
          ],
        )),
      );

      expect(find.text('Cancelado'), findsOneWidget);
      expect(find.text('Expirado'), findsOneWidget);
    });
  });

  group('ErrorState — tradução de erros (Fase 11)', () {
    testWidgets('sem rede diz "Sem ligação", não "Algo correu mal"',
        (tester) async {
      await tester.pumpWidget(
        wrap(ErrorState(
          error: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          ),
        )),
      );

      // Não correu nada mal — só não há rede. Dizer o contrário manda a
      // pessoa procurar um problema que não existe.
      expect(find.text('Sem ligação'), findsOneWidget);
      expect(find.text('Algo correu mal'), findsNothing);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('um erro desconhecido mantém a mensagem por omissão',
        (tester) async {
      await tester.pumpWidget(
        wrap(const ErrorState(
          error: 'qualquer coisa',
          message: 'Não foi possível carregar os planos.',
        )),
      );

      expect(find.text('Algo correu mal'), findsOneWidget);
      expect(find.text('Não foi possível carregar os planos.'), findsOneWidget);
    });
  });

  group('Avatar — acessibilidade (Fase 11)', () {
    testWidgets('anuncia o nome, não as iniciais', (tester) async {
      await tester.pumpWidget(wrap(const Avatar('Rita Ferreira')));

      // Um leitor de ecrã lia "RF". As iniciais são abreviatura visual;
      // para quem ouve, o que interessa é o nome.
      expect(
        tester.getSemantics(find.byType(Avatar)).label,
        contains('Rita Ferreira'),
      );
    });
  });
}
