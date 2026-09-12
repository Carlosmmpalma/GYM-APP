import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/firebase_providers.dart';
import 'application/providers/tenant_context_providers.dart';
import 'core/theme/app_theme.dart';
import 'presentation/widgets/auth_gate.dart';
import 'presentation/widgets/data_health_banner.dart';

class GymSaasApp extends ConsumerWidget {
  const GymSaasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(environmentConfigProvider).environment;
    // O nome que o sistema mostra (separador do browser, gestor de
    // tarefas do Android) sai da configuração do tenant desta build,
    // como o resto do branding. Estava aqui escrito à mão o nome
    // INTERNO do produto — no browser, isso substituía o título do
    // `index.html` e o separador dizia "Gym SaaS" a toda a gente.
    final tenant = ref.watch(tenantAppConfigProvider);

    return MaterialApp(
      title: tenant.displayName ?? 'Gym',
      debugShowCheckedModeBanner: false,
      // Fita no canto em tudo o que NÃO é produção.
      //
      // `flutter build web` sem `-t` compila `lib/main.dart`, que aponta
      // para **development**. Publicar esse artefacto por engano dava
      // uma app com aspeto normal a escrever na base de dados errada, e
      // ninguém dava por isso. A fita é o aviso que falta: se aparecer
      // no site do estúdio, foi publicada a build errada.
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        // O aviso de leitura falhada envolve TUDO, incluindo os ecrãs
        // que nunca trataram o erro — que são a maioria. Ver
        // `DataHealthBanner`.
        final comAviso = DataHealthBanner(child: child);
        if (environment.isProduction) return comAviso;
        return Banner(
          message: environment.label.toUpperCase(),
          location: BannerLocation.topEnd,
          color: Colors.deepOrange,
          child: comAviso,
        );
      },
      // Fase 10 — tema escuro do mockup (ver `core/theme/app_theme.dart`).
      // Só existe modo escuro: o mockup define UM produto, não um par
      // claro/escuro, e inventar uma variante clara seria desenhar algo
      // que ninguém aprovou. `darkTheme`/`themeMode` ficam de fora de
      // propósito — `theme` sozinho aplica-se sempre.
      theme: AppTheme.dark,
      // Substituir por um router real (ver Platform Foundation §10 —
      // camada Presentation) quando existir mais do que um punhado de
      // ecrãs. Por agora, AuthGate decide sozinho entre login/troca de
      // password/home (Fase 1).
      home: const AuthGate(),
    );
  }
}
