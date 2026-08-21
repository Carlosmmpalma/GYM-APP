import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/widgets/auth_gate.dart';

class GymSaasApp extends StatelessWidget {
  const GymSaasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym SaaS',
      debugShowCheckedModeBanner: false,
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
