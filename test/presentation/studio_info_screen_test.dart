import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/admin_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/environment.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/studio_info.dart';
import 'package:gym_saas/presentation/screens/studio_info_screen.dart';
import 'package:gym_saas/repositories/studio_admin_repository.dart';

class _FakeStudioAdmin implements StudioAdminRepository {
  StudioInfo? guardado;

  @override
  Future<void> updateStudioInfo(StudioInfo info) async {
    guardado = info;
  }
}

/// O ecrã onde o Gestor muda a morada do próprio ginásio sem precisar de
/// um developer e de uma versão nova da app.
///
/// A vitrina esconde o que está por preencher — o que é o comportamento
/// certo lá e um problema aqui, porque o que se esconde também se
/// esquece. Por isso metade destes testes é sobre o aviso.
void main() {
  late _FakeStudioAdmin admin;

  setUp(() {
    admin = _FakeStudioAdmin();
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

  Widget host(StudioInfo info) {
    return ProviderScope(
      overrides: [
        environmentConfigProvider
            .overrideWithValue(EnvironmentConfig.development),
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: 't1'),
        ),
        studioInfoProvider.overrideWith((ref) async => info),
        studioAdminRepositoryProvider.overrideWithValue(admin),
      ],
      child: const MaterialApp(home: StudioInfoScreen()),
    );
  }

  testWidgets('avisa o que falta, e a política em vermelho', (tester) async {
    // Sem a política de privacidade não há submissão possível nas lojas.
    // É a única coisa deste ecrã com esse peso, e é por isso que o aviso
    // muda de cor por causa dela.
    await tester.pumpWidget(host(const StudioInfo()));
    await tester.pumpAndSettle();

    expect(find.text('Falta preencher'), findsOneWidget);
    expect(
      find.textContaining('Política de privacidade'),
      findsWidgets,
    );
    expect(find.textContaining('Morada'), findsWidgets);
  });

  testWidgets('com tudo preenchido, não há aviso nenhum', (tester) async {
    await tester.pumpWidget(
      host(const StudioInfo(
        address: 'Rua de Exemplo 1',
        phone: '210 000 000',
        email: 'geral@exemplo.test',
        privacyPolicyUrl: 'https://exemplo.test/privacidade',
        openingHours: [
          OpeningHours(days: 'Segunda a sexta', hours: '07:00 – 22:00'),
        ],
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Falta preencher'), findsNothing);
  });

  testWidgets('traz o que já está guardado para os campos', (tester) async {
    // Valores diferentes dos `hintText` dos campos, de propósito: os
    // hints são texto no ecrã como qualquer outro, e usar os mesmos
    // valores fazia o teste encontrar cinco widgets e não saber qual.
    await tester.pumpWidget(
      host(const StudioInfo(
        address: 'Rua de Exemplo 1',
        phone: '210 000 000',
        openingHours: [
          OpeningHours(days: 'Todos os dias úteis', hours: '08:15 – 21:45'),
        ],
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rua de Exemplo 1'), findsOneWidget);
    expect(find.text('210 000 000'), findsOneWidget);
    expect(find.text('Todos os dias úteis'), findsOneWidget);
    expect(find.text('08:15 – 21:45'), findsOneWidget);
  });

  testWidgets('um endereço sem esquema é recusado antes de guardar',
      (tester) async {
    // Um "URL" assim abre uma página em branco no telemóvel e o Gestor
    // nunca saberia porquê — o botão simplesmente não faz nada.
    await tester.pumpWidget(host(const StudioInfo()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Política de privacidade publicada'),
      'exemplo.test/privacidade',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tem de começar por https://'),
      findsOneWidget,
    );
    expect(admin.guardado, isNull);
  });

  testWidgets('guarda o que o Gestor escreveu', (tester) async {
    await tester.pumpWidget(host(const StudioInfo()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Política de privacidade publicada'),
      'https://exemplo.test/privacidade',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Morada'),
      'Rua Nova 2, Lisboa',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
        admin.guardado?.privacyPolicyUrl, 'https://exemplo.test/privacidade');
    expect(admin.guardado?.address, 'Rua Nova 2, Lisboa');
  });

  testWidgets('sair sem tocar em nada não pergunta nada', (tester) async {
    // O `UnsavedChangesGuard` avisa quando há alterações por gravar. O
    // ecrã carrega os valores guardados para os campos — e isso dispara
    // o `onChanged` do `Form`, que é indistinguível de alguém a
    // escrever. Resultado: abrir o ecrã e sair perguntava "tens
    // alterações por gravar", sobre alterações que não existiam.
    // O `ProviderScope` por FORA do `MaterialApp`: a rota empilhada
    // pendura-se no Navigator, que está acima do `home` — com o scope lá
    // dentro, o ecrã novo não o encontrava.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider
              .overrideWithValue(EnvironmentConfig.development),
          tenantAppConfigProvider
              .overrideWithValue(const TenantAppConfig(tenantId: 't1')),
          studioInfoProvider.overrideWith(
            (ref) async => const StudioInfo(address: 'Rua de Exemplo 1'),
          ),
          studioAdminRepositoryProvider.overrideWithValue(admin),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StudioInfoScreen(),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Rua de Exemplo 1'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('por gravar'), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('mas sair depois de escrever avisa', (tester) async {
    // O outro lado do mesmo guarda: silenciá-lo bem é fácil se se
    // silenciar sempre.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider
              .overrideWithValue(EnvironmentConfig.development),
          tenantAppConfigProvider
              .overrideWithValue(const TenantAppConfig(tenantId: 't1')),
          studioInfoProvider.overrideWith(
            (ref) async => const StudioInfo(address: 'Rua de Exemplo 1'),
          ),
          studioAdminRepositoryProvider.overrideWithValue(admin),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StudioInfoScreen(),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Telefone'),
      '210 000 000',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('por gravar'), findsOneWidget);
  });
}
