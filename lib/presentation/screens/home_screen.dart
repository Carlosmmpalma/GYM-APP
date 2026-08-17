import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/notification_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import 'assessment_list_screen.dart';
import 'book_training_screen.dart';
import 'exercise_library_screen.dart';
import 'free_training_screen.dart';
import 'hello_world_screen.dart';
import 'instructor_calendar_screen.dart';
import 'instructor_home_screen.dart';
import 'instructor_students_screen.dart';
import 'manager_screen.dart';
import 'my_bookings_screen.dart';
import 'my_profile_screen.dart';
import 'my_training_plan_screen.dart';

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
    FreeTrainingScreen(),
    MyBookingsScreen(),
  ];

  static const _titles = ['Marcar treino', 'Treino livre', 'Minhas marcações'];

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
    final isManager = appUser?.isManager ?? false;

    if (appUser != null) {
      // Side effect, sem usar o resultado para construir UI — regista
      // o token de FCM deste dispositivo uma única vez por sessão de
      // login (o provider é `.family` por AppUser, cache do Riverpod
      // evita repetir a chamada em rebuilds seguintes).
      ref.listen(fcmTokenRegistrationProvider(appUser), (previous, next) {});
    }

    // Fase 8 (auditoria funcional) — um Instrutor PURO (nem Manager
    // nem membro) não tem plano nem marcações próprias: os separadores
    // "Marcar treino"/"Treino livre"/"Minhas marcações" não se
    // aplicam-lhe de todo. Passa a ver o dashboard do mockup
    // ("Início — Dashboard do instrutor") em vez deles. Um instrutor
    // que TAMBÉM é membro (Domain Model v1 §6) continua a ver os
    // separadores de Aluno, porque para esse lado da conta eles são
    // reais; as ferramentas de instrutor ficam nos ícones da AppBar,
    // como já estavam.
    final isPureInstructor = appUser != null &&
        appUser.isInstructor &&
        !isManager &&
        !appUser.isMember;

    return Scaffold(
      appBar: AppBar(
        title: Text(isPureInstructor ? 'Início' : _titles[_tabIndex]),
        actions: [
          if (isManager)
            IconButton(
              tooltip: 'Gestão',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManagerScreen()),
              ),
            ),
          // UC20 — um instrutor que também é MEMBRO continua a ver os
          // separadores de Aluno, por isso as ferramentas de instrutor
          // ficam aqui na AppBar. Um instrutor PURO já tem tudo isto
          // como cards no `InstructorHomeScreen` (Fase 8) — não
          // duplica. Um instrutor que também é Manager vê tudo a
          // partir de "Gestão", acima.
          if (appUser != null &&
              appUser.isInstructor &&
              !isManager &&
              !isPureInstructor) ...[
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
            // Fase 8 — mesmo raciocínio do calendário acima: um
            // instrutor puro não passa por "Gestão", mas precisa de
            // ver os alunos para avaliações/plano de treino (UC13/14/16).
            IconButton(
              tooltip: 'Alunos',
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const InstructorStudentsScreen()),
              ),
            ),
            // UC15 — atalho de topo, mesmo mockup do Home do
            // Instrutor ("Biblioteca de exercícios" ao lado de "Nova
            // avaliação").
            IconButton(
              tooltip: 'Biblioteca de exercícios',
              icon: const Icon(Icons.video_library_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ExerciseLibraryScreen()),
              ),
            ),
          ],
          // UC02 é especificamente o perfil do Aluno — `MyProfileScreen`
          // lê `members/{uid}`, que não existe para quem só tem
          // `staff/{uid}` (Leo, um Gestor sem ser também membro, por
          // exemplo). Staff que também é membro (Domain Model v1 §6 —
          // "instrutor que também é membro") continua a ver isto
          // normalmente, `isMember` cobre esse caso.
          if (appUser != null && appUser.isMember) ...[
            IconButton(
              tooltip: 'Perfil',
              icon: const Icon(Icons.person_outline),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyProfileScreen(memberId: appUser.uid),
                ),
              ),
            ),
            // Fase 8 (UC03) — "O meu plano" (série/reps/carga + vídeo
            // por exercício).
            IconButton(
              tooltip: 'O meu plano',
              icon: const Icon(Icons.fitness_center),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyTrainingPlanScreen(memberId: appUser.uid),
                ),
              ),
            ),
            // Fase 8 (UC04) — histórico de avaliações, mais recente
            // primeiro. Reutiliza `AssessmentListScreen`/
            // `AssessmentDetailScreen` (o mesmo ecrã que o
            // Instrutor/Gestor usam) — só o botão "Editar" no detalhe
            // fica escondido para um Aluno (`canEdit`, ver
            // `assessment_detail_screen.dart`).
            IconButton(
              tooltip: 'As minhas avaliações',
              icon: const Icon(Icons.assignment_outlined),
              onPressed: () async {
                final memberAsync =
                    await ref.read(memberProfileProvider(appUser.uid).future);
                if (memberAsync == null || !context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AssessmentListScreen(member: memberAsync),
                  ),
                );
              },
            ),
          ],
          IconButton(
            tooltip: 'Diagnóstico (Fase 0)',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelloWorldScreen()),
            ),
          ),
        ],
      ),
      body: isPureInstructor
          ? InstructorHomeScreen(appUser: appUser)
          : IndexedStack(index: _tabIndex, children: _screens),
      bottomNavigationBar: isPureInstructor
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (index) =>
                  setState(() => _tabIndex = index),
              destinations: const [
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
