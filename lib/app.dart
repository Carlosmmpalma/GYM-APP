import 'package:flutter/material.dart';

import 'presentation/widgets/auth_gate.dart';

class GymSaasApp extends StatelessWidget {
  const GymSaasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym SaaS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      // Substituir por um router real (ver Platform Foundation §10 —
      // camada Presentation) quando existir mais do que um punhado de
      // ecrãs. Por agora, AuthGate decide sozinho entre login/troca de
      // password/home (Fase 1).
      home: const AuthGate(),
    );
  }
}
