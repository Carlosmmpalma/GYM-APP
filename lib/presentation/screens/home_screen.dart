import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import 'book_training_screen.dart';
import 'hello_world_screen.dart';
import 'manager_screen.dart';
import 'my_bookings_screen.dart';
import 'my_profile_screen.dart';

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
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isManager = appUser?.isManager ?? false;

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
          // UC02 é especificamente o perfil do Aluno — `MyProfileScreen`
          // lê `members/{uid}`, que não existe para quem só tem
          // `staff/{uid}` (Leo, um Gestor sem ser também membro, por
          // exemplo). Staff que também é membro (Domain Model v1 §6 —
          // "instrutor que também é membro") continua a ver isto
          // normalmente, `isMember` cobre esse caso.
          if (appUser != null && appUser.isMember)
            IconButton(
              tooltip: 'Perfil',
              icon: const Icon(Icons.person_outline),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyProfileScreen(memberId: appUser.uid),
                ),
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
