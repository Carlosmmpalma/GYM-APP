import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/firebase_providers.dart';
import 'core/theme/app_theme.dart';
import 'presentation/widgets/auth_gate.dart';

class GymSaasApp extends ConsumerWidget {
  const GymSaasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(environmentConfigProvider).environment;

    return MaterialApp(
      title: 'Gym SaaS',
      debugShowCheckedModeBanner: false,
      // Fita no canto em tudo o que NÃO é produção.
      //
      // `flutter build web` sem `-t` compila `lib/main.dart`, que aponta
      // para **development**. Publicar esse artefacto por engano dava
      // uma app com aspeto normal a escrever na base de dados errada, e
      // ninguém dava por isso. A fita é o aviso que falta: se aparecer
      // no site do estúdio, foi publicada a build errada.
      builder: (context, child) {
        if (environment.isProduction || child == null) return child!;
        return Banner(
          message: environment.label.toUpperCase(),
          location: BannerLocation.topEnd,
          color: Colors.deepOrange,
          child: child,
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
