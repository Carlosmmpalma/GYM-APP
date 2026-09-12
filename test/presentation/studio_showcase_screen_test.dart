import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/core/config/environment.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/studio_info.dart';
import 'package:gym_saas/domain/entities/public_schedule.dart';
import 'package:gym_saas/presentation/screens/studio_showcase_screen.dart';

/// A vitrina é o primeiro ecrã da app para quem ainda não tem conta.
/// Vive de dados que podem faltar — config por preencher, mapa de aulas
/// que o cron ainda não escreveu — e o que interessa provar é que ela se
/// cala em vez de mostrar lixo.
void main() {
  // A vitrina é um ecrã alto e a `ListView` só constrói o que se vê —
  // com a superfície de teste por omissão (800x600), metade do conteúdo
  // não existe no widget tree e os `find` não o encontram. Isto não é um
  // problema do ecrã, é do tamanho da janela do teste.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  const info = StudioInfo(
    address: 'Rua de Exemplo 1, Lisboa',
    phone: '210 000 000',
    email: 'geral@exemplo.test',
    privacyPolicyUrl: 'https://exemplo.test/privacidade',
    openingHours: [
      OpeningHours(days: 'Segunda a sexta', hours: '07:00 – 22:00'),
      // Linha por preencher: não deve aparecer.
      OpeningHours(days: '', hours: ''),
    ],
  );

  Widget host({StudioInfo studioInfo = info, PublicSchedule? schedule}) {
    return ProviderScope(
      overrides: [
        environmentConfigProvider
            .overrideWithValue(EnvironmentConfig.development),
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(
            tenantId: 't1',
            displayName: 'Estúdio de Teste',
          ),
        ),
        studioInfoProvider.overrideWith((ref) async => studioInfo),
        publicScheduleProvider.overrideWith(
          (ref) async => schedule ?? const PublicSchedule(entries: []),
        ),
      ],
      child: const MaterialApp(home: StudioShowcaseScreen()),
    );
  }

  PublicSchedule scheduleComAulas({Duration idade = Duration.zero}) {
    return PublicSchedule(
      updatedAt: DateTime.now().subtract(idade),
      entries: const [
        PublicScheduleEntry(
          name: 'Hyrox',
          dayOfWeek: 1,
          startTime: '19:00',
          durationMinutes: 60,
          capacity: 8,
        ),
      ],
    );
  }

  testWidgets('mostra o caminho para o login sem o impor', (tester) async {
    // O ponto da vitrina: a porta de entrada deixa de ser um formulário
    // de password, mas quem já é membro continua a chegar lá num toque.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Já sou membro — entrar'), findsOneWidget);
  });

  testWidgets('mostra morada, contactos e horário do estúdio', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Rua de Exemplo 1, Lisboa'), findsOneWidget);
    expect(find.text('210 000 000'), findsOneWidget);
    expect(find.text('geral@exemplo.test'), findsOneWidget);
    expect(find.text('07:00 – 22:00'), findsOneWidget);
  });

  testWidgets('uma linha de horário por preencher não aparece', (tester) async {
    // Esconder é melhor do que mostrar a marca a um utilizador; quem
    // apanha o esquecimento é `tenant_app_config_test.dart`, antes de a
    // build sair.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Domingo'), findsNothing);
    expect(find.textContaining('POR PREENCHER'), findsNothing);
  });

  testWidgets('sem informação preenchida, o ecrã continua utilizável',
      (tester) async {
    await tester.pumpWidget(host(studioInfo: const StudioInfo()));
    await tester.pumpAndSettle();

    expect(find.text('Já sou membro — entrar'), findsOneWidget);
    expect(find.text('ONDE ESTAMOS'), findsNothing);
  });

  testWidgets('mostra o mapa de aulas quando é recente', (tester) async {
    await tester.pumpWidget(host(schedule: scheduleComAulas()));
    await tester.pumpAndSettle();

    expect(find.text('MAPA DE AULAS'), findsOneWidget);
    expect(find.text('Hyrox'), findsOneWidget);
    expect(find.text('Segunda'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
  });

  testWidgets('cala-se sobre um mapa de aulas velho', (tester) async {
    // O cron corre todos os dias. Oito dias de silêncio significam que
    // alguma coisa parou — e um horário público errado manda pessoas ao
    // ginásio à hora errada, o que é pior do que não anunciar nada.
    await tester.pumpWidget(
      host(schedule: scheduleComAulas(idade: const Duration(days: 8))),
    );
    await tester.pumpAndSettle();

    expect(find.text('MAPA DE AULAS'), findsNothing);
    expect(find.text('Hyrox'), findsNothing);
  });

  testWidgets('cala-se quando ainda não há mapa nenhum', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('MAPA DE AULAS'), findsNothing);
  });

  testWidgets('a política de privacidade está sempre disponível',
      (tester) async {
    // Vive dentro da app e não depende de o estúdio ter publicado nada.
    await tester.pumpWidget(host(studioInfo: const StudioInfo()));
    await tester.pumpAndSettle();

    expect(find.text('Ler a política de privacidade'), findsOneWidget);
  });
}
