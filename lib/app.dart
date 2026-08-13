import 'package:flutter/material.dart';

import 'presentation/screens/hello_world_screen.dart';

class GymSaasApp extends StatelessWidget {
  const GymSaasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym SaaS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      // Substituir por um router real (ver Platform Foundation §10 —
      // camada Presentation) quando existir mais do que um ecrã.
      home: const HelloWorldScreen(),
    );
  }
}
