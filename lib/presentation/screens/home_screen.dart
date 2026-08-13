import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import 'book_training_screen.dart';
import 'hello_world_screen.dart';
import 'manager_screen.dart';
import 'my_bookings_screen.dart';

/// Ecrã principal pós-login (substitui o HelloWorldScreen como destino
/// do AuthGate a partir da Fase 2). O diagnóstico da Fase 0 continua
/// acessível — só deixou de ser a primeira coisa que se vê.
///
/// Sem router (Platform Foundation §10 já previa isto: "Substituir por
/// um router real quando existir mais do que um punhado de ecrãs" —
/// ainda não chegámos lá).
///
/// `ConsumerStatefulWidget` desde a Fase 3 — precisa de ler
/// `currentAppUserProvider` para decidir se mostra a entrada de Gestão
/// (`AppUser.isManager`). Isto é só UI: quem impede um não-manager de
/// fazer algo são as Security Rules / a Cloud Function do lado do
/// servidor, não este `if`.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tabIndex = 0;

  static const _screens = [
    BookTrainingScreen(),
    MyBookingsScreen(),
  ];

  static const _titles = ['Marcar treino', 'Minhas marcações'];

  @override
  Widget build(BuildContext context) {
    final isManager =
        ref.watch(currentAppUserProvider).valueOrNull?.isManager ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tabIndex]),
        actions: [
          if (isManager)
            IconButton(
              tooltip: 'Gestão',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManagerScreen()),
              ),
            ),
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
