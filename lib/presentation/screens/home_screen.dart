import 'package:flutter/material.dart';

import 'book_training_screen.dart';
import 'hello_world_screen.dart';
import 'my_bookings_screen.dart';

/// Ecrã principal pós-login (substitui o HelloWorldScreen como destino
/// do AuthGate a partir da Fase 2). O diagnóstico da Fase 0 continua
/// acessível — só deixou de ser a primeira coisa que se vê.
///
/// Sem router (Platform Foundation §10 já previa isto: "Substituir por
/// um router real quando existir mais do que um punhado de ecrãs" —
/// ainda não chegámos lá).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  static const _screens = [
    BookTrainingScreen(),
    MyBookingsScreen(),
  ];

  static const _titles = ['Marcar treino', 'Minhas marcações'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tabIndex]),
        actions: [
          IconButton(
            tooltip: 'Diagnóstico (Fase 0)',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelloWorldScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tabIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            label: 'Marcar',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            label: 'Marcações',
          ),
        ],
      ),
    );
  }
}
