import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/app.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/environment.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';

/// `flutter build web` sem `-t` compila `lib/main.dart`, que aponta
/// para **development**. Publicar esse artefacto por engano dava uma
/// app com aspeto normal a escrever na base de dados errada — e ninguém
/// dava por isso até ser tarde.
///
/// A fita no canto é o aviso que faltava. Este teste existe para que
/// ela não desapareça numa limpeza distraída.
void main() {
  Widget buildApp(EnvironmentConfig config) {
    return ProviderScope(
      overrides: [
        environmentConfigProvider.overrideWithValue(config),
        // O título da app passou a sair da configuração do tenant desta
        // build (é o nome do ginásio, não o do produto).
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(
            tenantId: 'tenant_test',
            displayName: 'NXT Performance Studio',
          ),
        ),
      ],
      child: const GymSaasApp(),
    );
  }

  testWidgets('development mostra a fita', (tester) async {
    await tester.pumpWidget(buildApp(EnvironmentConfig.development));
    await tester.pump();

    final banners = tester.widgetList<Banner>(find.byType(Banner));
    expect(
      banners.map((b) => b.message),
      contains('DEVELOPMENT'),
    );
  });

  testWidgets('staging também', (tester) async {
    await tester.pumpWidget(buildApp(EnvironmentConfig.staging));
    await tester.pump();

    final banners = tester.widgetList<Banner>(find.byType(Banner));
    expect(banners.map((b) => b.message), contains('STAGING'));
  });

  testWidgets('produção não mostra fita nenhuma', (tester) async {
    // Se esta falhar, a app real ficou com uma tarja laranja no canto.
    await tester.pumpWidget(buildApp(EnvironmentConfig.production));
    await tester.pump();

    final banners = tester.widgetList<Banner>(find.byType(Banner));
    expect(
      banners.map((b) => b.message),
      isNot(anyOf(contains('DEVELOPMENT'), contains('STAGING'))),
    );
  });
}
