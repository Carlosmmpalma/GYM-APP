import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/notification_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/app_user.dart';
import 'book_training_screen.dart';
import 'exercise_library_screen.dart';
import 'free_training_screen.dart';
import 'gestor_dashboard_screen.dart';
import 'instructor_calendar_screen.dart';
import 'instructor_home_screen.dart';
import 'instructor_students_screen.dart';
import 'manager_screen.dart';
import 'member_home_screen.dart';
import 'my_bookings_screen.dart';
import 'my_profile_screen.dart';

/// Ecrã principal pós-login (destino do AuthGate a partir da Fase 2).
///
/// Fase 10 — saiu daqui o botão de diagnóstico da Fase 0 (o ícone de
/// insecto na AppBar). Existia para provar o critério "Done" da Fase 0
/// ("a app liga ao emulador e lê/escreve um documento de teste") e
/// arrastou-se por todas as fases seguintes num sítio visível a
/// utilizadores reais. Ver README, "Restos da fase de arranque".
///
/// Sem router (Platform Foundation §10 já previa isto: "Substituir por
/// um router real quando existir mais do que um punhado de ecrãs" —
/// ainda não chegámos lá).
///
/// Fase 10 — a app passou a ter TRÊS shells, um por papel, em vez de um
/// só com ícones condicionais na `AppBar`. Antes, um Gestor via os
/// separadores do Aluno ("Marcar treino", "Treino livre", "Minhas
/// marcações") — coisas que ele não faz — e a Gestão estava escondida
/// atrás de um ícone sem rótulo no canto. A queixa foi literal: não se
/// percebia o que fazer nem como a app funciona.
///
///   Gestor      → Visão global · Gestão (+ Treino, se também for membro)
///   Instrutor   → dashboard do instrutor (sem separadores)
///   Aluno       → Início · Marcar · Livre · Marcações
///
/// A ordem de decisão é Gestor → Instrutor puro → Aluno: quem acumula
/// papéis vê o shell do papel mais abrangente, e as funções do outro
/// continuam alcançáveis a partir dele (o Gestor tem "Alunos — treino"
/// dentro de Gestão; um Gestor que treina tem o separador "Treino").
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // UC21 — mensagens em primeiro plano não mostram nenhuma UI por
    // omissão do FCM (só em segundo plano/terminado, via o sistema
    // operativo); isto é o mínimo para o utilizador ver algo enquanto
    // usa a app. Sem `flutter_local_notifications` (pacote novo, fora
    // de âmbito desta fase) — só um SnackBar.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${notification.title ?? ''}: ${notification.body ?? ''}'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;

    if (appUser != null) {
      // Side effect, sem usar o resultado para construir UI — regista
      // o token de FCM deste dispositivo uma única vez por sessão de
      // login (o provider é `.family` por AppUser, cache do Riverpod
      // evita repetir a chamada em rebuilds seguintes).
      ref.listen(fcmTokenRegistrationProvider(appUser), (previous, next) {});
    }

    if (appUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (appUser.isManager) return _buildManagerShell(appUser);
    if (appUser.isInstructor && !appUser.isMember) {
      return _buildInstructorShell(appUser);
    }
    return _buildMemberShell(appUser);
  }

  /// Gestor — "Visão global" primeiro (a pergunta com que se abre a app:
  /// como está o ginásio hoje), Gestão a seguir. O separador "Treino" só
  /// existe se ele também tiver conta de membro; um Gestor puro nunca vê
  /// ecrãs de marcação, que era exatamente o pedido.
  Widget _buildManagerShell(AppUser appUser) {
    final alsoMember = appUser.isMember;
    final titles = ['Visão global', 'Gestão', if (alsoMember) 'O meu treino'];
    final index = _tabIndex.clamp(0, titles.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text(titles[index])),
      body: IndexedStack(
        index: index,
        children: [
          const GestorDashboardScreen(),
          const ManagerScreen(),
          if (alsoMember)
            // `onOpenTab` omitido: aqui os atalhos empilham ecrãs, em
            // vez de trocar de separador — os separadores deste shell
            // são de gestão, não de treino.
            MemberHomeScreen(memberId: appUser.uid),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Visão global',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            label: 'Gestão',
          ),
          if (alsoMember)
            const NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              label: 'Treino',
            ),
        ],
      ),
    );
  }

  /// Instrutor puro — o dashboard do mockup já é o ecrã inteiro, com os
  /// seus próprios cards; não há um segundo sítio para onde ir que
  /// justifique uma barra inferior.
  Widget _buildInstructorShell(AppUser appUser) {
    return Scaffold(
      appBar: AppBar(title: const Text('Início')),
      body: InstructorHomeScreen(appUser: appUser),
    );
  }

  Widget _buildMemberShell(AppUser appUser) {
    const titles = [
      'Início',
      'Marcar treino',
      'Treino livre',
      'Minhas marcações',
    ];
    final index = _tabIndex.clamp(0, titles.length - 1);

    // Um Instrutor que TAMBÉM é membro vê os separadores de Aluno (para
    // esse lado da conta são reais) e as ferramentas de instrutor ficam
    // na AppBar — não há um terceiro shell só para esta combinação.
    final showInstructorTools = appUser.isInstructor;

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[index]),
        actions: [
          if (showInstructorTools) ...[
            IconButton(
              tooltip: 'As minhas aulas',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      InstructorCalendarScreen(instructorId: appUser.uid),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Alunos',
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InstructorStudentsScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Biblioteca de exercícios',
              icon: const Icon(Icons.video_library_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ExerciseLibraryScreen()),
              ),
            ),
          ],
          // "O meu plano" e "As minhas avaliações" saíram daqui na Fase
          // 10 — são cards nomeados no dashboard "Início". "Perfil"
          // fica, porque o mockup também o tem no topo do "Início".
          IconButton(
            tooltip: 'Perfil',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MyProfileScreen(memberId: appUser.uid),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: [
          MemberHomeScreen(
            memberId: appUser.uid,
            onOpenTab: (i) => setState(() => _tabIndex = i),
          ),
          const BookTrainingScreen(),
          const FreeTrainingScreen(),
          const MyBookingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            label: 'Marcar',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            label: 'Livre',
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
