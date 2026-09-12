import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/admin_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/assessment.dart';
import 'package:gym_saas/domain/entities/exercise.dart';
import 'package:gym_saas/domain/entities/free_training_slot.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/plan.dart';
import 'package:gym_saas/domain/entities/retention_overview.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/session_series.dart';
import 'package:gym_saas/domain/entities/staff_summary.dart';
import 'package:gym_saas/domain/entities/workout_session.dart';
import 'package:gym_saas/presentation/screens/account_blocked_screen.dart';
import 'package:gym_saas/presentation/screens/active_workout_screen.dart';
import 'package:gym_saas/presentation/screens/add_plan_entry_screen.dart';
import 'package:gym_saas/presentation/screens/assessment_detail_screen.dart';
import 'package:gym_saas/presentation/screens/assessment_form_screen.dart';
import 'package:gym_saas/presentation/screens/assessment_list_screen.dart';
import 'package:gym_saas/presentation/screens/assign_subscription_screen.dart';
import 'package:gym_saas/presentation/screens/book_training_screen.dart';
import 'package:gym_saas/presentation/screens/consent_screen.dart';
import 'package:gym_saas/presentation/screens/create_series_screen.dart';
import 'package:gym_saas/presentation/screens/create_user_screen.dart';
import 'package:gym_saas/presentation/screens/exercise_form_screen.dart';
import 'package:gym_saas/presentation/screens/exercise_library_screen.dart';
import 'package:gym_saas/presentation/screens/exercise_video_screen.dart';
import 'package:gym_saas/presentation/screens/force_password_change_screen.dart';
import 'package:gym_saas/presentation/screens/free_training_screen.dart';
import 'package:gym_saas/presentation/screens/free_training_slot_detail_screen.dart';
import 'package:gym_saas/presentation/screens/gestor_dashboard_screen.dart';
import 'package:gym_saas/presentation/screens/group_workout_screen.dart';
import 'package:gym_saas/presentation/screens/home_screen.dart';
import 'package:gym_saas/presentation/screens/instructor_calendar_screen.dart';
import 'package:gym_saas/presentation/screens/instructor_home_screen.dart';
import 'package:gym_saas/presentation/screens/instructor_students_screen.dart';
import 'package:gym_saas/presentation/screens/load_evolution_screen.dart';
import 'package:gym_saas/presentation/screens/login_screen.dart';
import 'package:gym_saas/presentation/screens/manage_exercise_categories_screen.dart';
import 'package:gym_saas/presentation/screens/manage_free_training_screen.dart';
import 'package:gym_saas/presentation/screens/manage_members_screen.dart';
import 'package:gym_saas/presentation/screens/manage_modalities_screen.dart';
import 'package:gym_saas/presentation/screens/manage_payments_screen.dart';
import 'package:gym_saas/presentation/screens/manage_plans_screen.dart';
import 'package:gym_saas/presentation/screens/manage_series_screen.dart';
import 'package:gym_saas/presentation/screens/manage_services_screen.dart';
import 'package:gym_saas/presentation/screens/manage_staff_screen.dart';
import 'package:gym_saas/presentation/screens/manage_users_screen.dart';
import 'package:gym_saas/presentation/screens/manager_screen.dart';
import 'package:gym_saas/presentation/screens/member_detail_screen.dart';
import 'package:gym_saas/presentation/screens/member_home_screen.dart';
import 'package:gym_saas/presentation/screens/member_stats_screen.dart';
import 'package:gym_saas/presentation/screens/my_bookings_screen.dart';
import 'package:gym_saas/presentation/screens/my_profile_screen.dart';
import 'package:gym_saas/presentation/screens/my_training_plan_screen.dart';
import 'package:gym_saas/presentation/screens/occurrence_detail_screen.dart';
import 'package:gym_saas/presentation/screens/payment_history_screen.dart';
import 'package:gym_saas/presentation/screens/plan_detail_screen.dart';
import 'package:gym_saas/presentation/screens/privacy_policy_screen.dart';
import 'package:gym_saas/presentation/screens/retention_screen.dart';
import 'package:gym_saas/presentation/screens/send_notification_screen.dart';
import 'package:gym_saas/presentation/screens/series_detail_screen.dart';
import 'package:gym_saas/presentation/screens/staff_detail_screen.dart';
import 'package:gym_saas/presentation/screens/studio_info_screen.dart';
import 'package:gym_saas/presentation/screens/student_training_screen.dart';
import 'package:gym_saas/presentation/screens/studio_showcase_screen.dart';
import 'package:gym_saas/presentation/screens/tenant_settings_screen.dart';
import 'package:gym_saas/presentation/screens/training_plan_editor_screen.dart';
import 'package:gym_saas/presentation/screens/workout_history_screen.dart';
import 'package:gym_saas/presentation/widgets/design_system.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import '../support/device_matrix.dart';

/// Cada ecrã da app, em cada tamanho de telemóvel onde vai correr.
///
/// ## O que isto procura
///
/// `RenderFlex overflowed`. O Flutter desenha as barras amarelas e
/// pretas por cima do conteúdo e o que ficou de fora deixa de ser
/// tocável — um botão "Confirmar" empurrado para lá da margem é uma
/// funcionalidade que não existe naquele telefone.
///
/// Não é preciso escrever asserções para isto: o framework reporta um
/// `FlutterError` e o teste falha sozinho. O que faltava era pôr os
/// ecrãs em tamanhos onde acontece — todos os testes de widget deste
/// projeto corriam no ecrã por omissão do `flutter_test`, 800×600, que
/// é mais largo do que qualquer iPhone e mais baixo do que todos.
///
/// ## A armadilha que isto tem de evitar
///
/// Um ecrã de erro cabe sempre. Se o fixture estiver incompleto, o
/// provider falha, o ecrã mostra um [ErrorState] com três linhas, e o
/// teste passa em verde sem ter testado nada — a pior espécie de teste,
/// porque dá confiança em vez de a medir.
///
/// Por isso cada caso verifica DUAS coisas: que não estourou, e que o
/// que está no ecrã é conteúdo a sério.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  // -------------------------------------------------------------------
  // Um estúdio completo, partilhado por todos os ecrãs
  // -------------------------------------------------------------------
  //
  // Deliberadamente com dados LONGOS: nomes compridos, descrições
  // compridas, valores com cêntimos. Um fixture de "Ana" e "Plano A"
  // cabe em qualquer ecrã e não prova nada — os nomes reais de um
  // estúdio português têm apelidos, e é aí que as linhas estouram.
  Future<FakeFirebaseFirestore> semear() async {
    final firestore = FakeFirebaseFirestore();
    final tenant = firestore.collection('tenants').doc(_tenantId);
    final agora = DateTime.now();

    await tenant.set({'name': 'NXT Performance Studio'});

    await tenant.collection('public').doc('info').set({
      'displayName': 'NXT Performance Studio',
      'address': 'Travessa de São Vicente, Ferreira do Alentejo',
      'phone': '+351 912 345 678',
      'email': 'geral@nxtperformancestudio.pt',
      'openingHours': [
        {'days': 'Segunda a sexta', 'hours': '07:00 – 13:00, 16:00 – 21:30'},
        {'days': 'Sábado', 'hours': '09:00 – 13:00'},
      ],
      'updatedAt': Timestamp.fromDate(agora),
    });

    await tenant.collection('public').doc('schedule').set({
      'generatedAt': Timestamp.fromDate(agora),
      'entries': [
        {
          'serviceName': 'Treino Funcional em Grupo',
          'dayOfWeek': DateTime.monday,
          'startTime': '18:30',
          'durationMinutes': 60,
        },
        {
          'serviceName': 'Pilates Clínico',
          'dayOfWeek': DateTime.wednesday,
          'startTime': '19:00',
          'durationMinutes': 50,
        },
      ],
    });

    for (final (id, nome) in const [
      ('service_1', 'Treino Funcional em Grupo'),
      ('service_2', 'Pilates Clínico'),
    ]) {
      await tenant.collection('services').doc(id).set({
        'name': nome,
        'active': true,
      });
    }

    await tenant.collection('modalities').doc('mod_1').set({
      'name': 'Condicionamento Físico Geral',
      'active': true,
      'serviceIds': ['service_1'],
    });

    await tenant.collection('plans').doc('plan_1').set({
      'name': 'Plano Ilimitado Anual',
      'description':
          'Acesso a todas as aulas de grupo e treino livre, sem limite '
              'semanal, com avaliação física trimestral incluída.',
      'currentPrice': 49.90,
      'currency': 'EUR',
      'active': true,
    });

    for (final (uid, numero, nome, estado) in const [
      ('member_1', '000142', 'Maria Madalena Gonçalves', 'active'),
      ('member_2', '000143', 'Alexandre Nascimento Rodrigues', 'active'),
      ('member_3', '000144', 'Constança Vasconcelos', 'inactive'),
    ]) {
      await tenant.collection('members').doc(uid).set({
        'memberNumber': numero,
        'name': nome,
        'status': estado,
        'email': '$uid@nxtperformancestudio.pt',
        'phone': '+351 912 345 678',
        'currentPaymentStatus': 'paid',
        'currentPaymentPeriod':
            '${agora.year}-${agora.month.toString().padLeft(2, '0')}',
      });
    }

    await tenant.collection('subscriptions').doc('sub_1').set({
      'memberId': 'member_1',
      'planId': 'plan_1',
      'status': 'active',
      'startDate': Timestamp.fromDate(agora.subtract(const Duration(days: 90))),
      'agreedPrice': 49.90,
      'currency': 'EUR',
      'activeServiceIds': ['service_1', 'service_2'],
    });

    await tenant.collection('staff').doc(_instrutorId).set({
      'name': 'Bernardo Albuquerque Teixeira',
      'roles': ['instructor'],
      'status': 'active',
      'email': 'bernardo@nxtperformancestudio.pt',
      'modalityIds': ['mod_1'],
    });

    await tenant.collection('sessionSeries').doc('series_1').set({
      'serviceId': 'service_1',
      'instructorId': _instrutorId,
      'dayOfWeek': DateTime.monday,
      'startTime': '18:30',
      'durationMinutes': 60,
      'capacity': 12,
      'startDate': Timestamp.fromDate(agora),
      'preAssignedMemberIds': <String>[],
      'status': 'active',
    });

    for (var i = 0; i < 3; i++) {
      final inicio = agora.add(Duration(days: i + 1, hours: 2));
      final occ = tenant.collection('sessionOccurrences').doc('occ_$i');
      await occ.set({
        'serviceId': 'service_1',
        'seriesId': 'series_1',
        'instructorId': _instrutorId,
        'startAt': Timestamp.fromDate(inicio),
        'endAt': Timestamp.fromDate(inicio.add(const Duration(hours: 1))),
        'capacity': 12,
        'status': 'scheduled',
        'activeBookingCount': 1,
        'reminderSentAt': null,
      });
      await occ.collection('bookings').doc('member_1').set({
        'memberId': 'member_1',
        'status': 'booked',
        'source': 'self',
        'isExtra': false,
        'serviceId': 'service_1',
        'startAt': Timestamp.fromDate(inicio),
        'createdAt': Timestamp.fromDate(agora),
      });
    }

    for (final (id, nome, categoria) in const [
      ('ex_1', 'Agachamento com Barra Livre', 'Membros inferiores'),
      ('ex_2', 'Supino Inclinado com Halteres', 'Membros superiores'),
    ]) {
      await tenant.collection('exercises').doc(id).set({
        'name': nome,
        'category': categoria,
        'description':
            'Manter a coluna neutra durante todo o movimento e controlar '
                'a fase excêntrica em três segundos.',
      });
    }

    return firestore;
  }

  // -------------------------------------------------------------------
  // O andaime comum
  // -------------------------------------------------------------------
  Widget app(
    FakeFirebaseFirestore firestore,
    Widget ecra, {
    required Set<Role> papeis,
    required bool precisaScaffold,
  }) {
    return ProviderScope(
      overrides: [
        // A retenção é calculada no servidor — `getRetentionOverview`.
        // Sem isto o ecrã mostra um erro, e um erro cabe em qualquer
        // telemóvel: a matriz passaria a verde sem medir o painel.
        retentionOverviewProvider.overrideWith((ref, args) async => _retencao),
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        functionsProvider.overrideWithValue(_FakeFunctions()),
        firebaseStorageProvider.overrideWithValue(_FakeStorage()),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            AppUser(
              uid: papeis.contains(Role.manager)
                  ? _gestorId
                  : papeis.contains(Role.instructor)
                      ? _instrutorId
                      : 'member_1',
              tenantId: _tenantId,
              roles: papeis,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        // `ManagerScreen` e `MemberHomeScreen` são CORPOS de separador,
        // não ecrãs completos — vivem dentro do `Scaffold` do
        // `HomeScreen`. Postos como `home:` diretamente, rebentam com
        // "No Material widget found", que é um defeito do andaime e não
        // da app.
        home: precisaScaffold ? Scaffold(body: ecra) : ecra,
      ),
    );
  }

  // -------------------------------------------------------------------
  // A matriz
  // -------------------------------------------------------------------
  for (final caso in _casos) {
    group(caso.nome, () {
      for (final d in dispositivos) {
        testWidgets('cabe em $d', (tester) async {
          aplicarDispositivo(tester, d);
          final firestore = await semear();

          await tester.pumpWidget(
            app(
              firestore,
              caso.construir(),
              papeis: caso.papeis,
              precisaScaffold: caso.precisaScaffold,
            ),
          );
          await assentar(tester);

          // Se o fixture não servir, o ecrã mostra um erro — e um erro
          // cabe em qualquer telemóvel. Sem isto, a matriz inteira
          // passava a verde sem ter medido nada.
          expect(
            find.byType(ErrorState),
            findsNothing,
            reason: '${caso.nome} mostrou um ErrorState — o fixture não chega '
                'para este ecrã, e o que a matriz mediu foi o ecrã de erro.',
          );

          // Um ecrã em branco também cabe. Exigir texto visível garante
          // que houve mesmo um layout para medir.
          expect(
            find.byType(Text),
            findsWidgets,
            reason: '${caso.nome} não desenhou texto nenhum.',
          );
        });
      }
    });
  }
}

const _tenantId = 'tenant_test';
const _gestorId = 'gestor_1';
const _instrutorId = 'instructor_1';

/// O membro que os ecrãs de detalhe recebem por argumento.
///
/// Nome comprido de propósito: um fixture de "Ana" cabe em qualquer
/// ecrã e não prova nada. Os nomes reais de um estúdio português têm
/// apelidos, e é numa `Row` com um nome destes que a linha estoura.
const _membro = MemberSummary(
  uid: 'member_1',
  memberNumber: '000142',
  name: 'Maria Madalena Gonçalves',
  active: true,
  phone: '+351 912 345 678',
  email: 'maria.goncalves@nxtperformancestudio.pt',
  address: 'Travessa de São Vicente, 14, 7900-000 Ferreira do Alentejo',
  nif: '123456789',
  emergencyContact: 'Alexandre Rodrigues · +351 913 000 111',
);

const _instrutorUser = AppUser(
  uid: _instrutorId,
  tenantId: _tenantId,
  roles: {Role.instructor},
);

/// As entidades que os ecrãs de detalhe recebem por argumento.
///
/// Todas com conteúdo do tamanho do real — um "Plano A" de 6 letras
/// cabe em qualquer sítio e não testa nada.

const _plano = Plan(
  id: 'plan_1',
  name: 'Plano Ilimitado Anual com Avaliação',
  description: 'Acesso a todas as aulas de grupo e treino livre, sem '
      'limite semanal, com avaliação física trimestral incluída.',
  currentPrice: 49.90,
  currency: 'EUR',
  active: true,
);

const _instrutorStaff = StaffSummary(
  uid: _instrutorId,
  name: 'Bernardo Albuquerque Teixeira',
  email: 'bernardo.teixeira@nxtperformancestudio.pt',
  roles: {Role.instructor},
  active: true,
);

const _exercicio = Exercise(
  id: 'ex_1',
  name: 'Agachamento com Barra Livre',
  description: 'Manter a coluna neutra durante todo o movimento e '
      'controlar a fase excêntrica em três segundos.',
  category: 'Membros inferiores',
);

final _serie = SessionSeries(
  id: 'series_1',
  serviceId: 'service_1',
  dayOfWeek: DateTime.monday,
  startTime: '18:30',
  durationMinutes: 60,
  capacity: 12,
  startDate: DateTime.now(),
  status: SessionSeriesStatus.active,
  instructorId: _instrutorId,
);

final _slot = FreeTrainingSlot(
  id: 'slot_1',
  weekId: '2026-W38',
  serviceId: 'service_1',
  startAt: DateTime.now().add(const Duration(days: 1)),
  endAt: DateTime.now().add(const Duration(days: 1, hours: 1)),
  capacity: 8,
  activeBookingCount: 3,
);

/// Um treino a decorrer, com séries já registadas — o estado em que o
/// ecrã tem mais conteúdo, que é o que interessa medir.
final _treino = WorkoutSession(
  id: 'ws_1',
  memberId: 'member_1',
  workoutName: 'Treino A · Membros inferiores e core',
  startedAt: DateTime.now().subtract(const Duration(minutes: 25)),
  performedBy: 'member_1',
  sets: [
    for (var i = 1; i <= 3; i++)
      SetLog(
        exerciseId: 'ex_1',
        setNumber: i,
        reps: 12,
        load: 60 + i * 2.5,
        completedAt: DateTime.now().subtract(Duration(minutes: 20 - i * 5)),
      ),
  ],
);

final _avaliacao = Assessment(
  id: 'av_1',
  memberId: 'member_1',
  instructorId: _instrutorId,
  createdAt: DateTime.now().subtract(const Duration(days: 14)),
  idade: 34,
  peso: 72.4,
  altura: 171,
  percentMassaGorda: 24.1,
  massaMuscular: 28.7,
  gorduraVisceral: 6,
  metabolismoBasal: 1486,
  percentAgua: 52.3,
  idadeMetabolica: 29,
  pressaoArterial: '118/76',
  perimetroCintura: 78.5,
  perimetroAbdominal: 84.0,
  forcaMS: 'Bom',
  forcaMI: 'Muito bom',
  forcaCore: 'Razoável',
  flexibilidade: 'Razoável',
  resistencia: 'Bom',
);

class _FakeFunctions extends Mock implements FirebaseFunctions {}

class _FakeStorage extends Mock implements FirebaseStorage {}

/// Um ecrã e quem o abre.
class _Caso {
  const _Caso(
    this.nome,
    this.construir, {
    this.papeis = const {Role.member},
    this.precisaScaffold = false,
  });
  final String nome;
  final Widget Function() construir;
  final Set<Role> papeis;

  /// Corpos de separador, que já contam com o `Scaffold` do
  /// `HomeScreen` por cima.
  final bool precisaScaffold;
}

final _retencao = RetentionOverview(
  windowDays: 30,
  riskWeeks: 3,
  scanDays: 90,
  membersWithActivePlan: 87,
  sessions: 164,
  occupancyPercent: 73,
  attendanceRecorded: 1528,
  noShows: 112,
  noShowPercent: 7,
  atRisk: [
    MemberAtRisk(
      memberId: 'member_3',
      name: 'Constança Vasconcelos',
      memberNumber: '000144',
      lastAttendanceAt: DateTime.now().subtract(const Duration(days: 41)),
    ),
    const MemberAtRisk(
      memberId: 'member_2',
      name: 'Alexandre Nascimento Rodrigues',
      memberNumber: '000143',
      lastAttendanceAt: null,
    ),
  ],
);

const _gestor = {Role.manager};
const _instrutor = {Role.instructor};

final _casos = <_Caso>[
  // Antes de entrar
  _Caso('StudioShowcaseScreen', () => const StudioShowcaseScreen()),
  _Caso('LoginScreen', () => const LoginScreen()),
  _Caso('PrivacyPolicyScreen', () => const PrivacyPolicyScreen()),
  _Caso('ConsentScreen', () => const ConsentScreen()),
  _Caso('AccountBlockedScreen', () => const AccountBlockedScreen()),
  _Caso(
    'ForcePasswordChangeScreen',
    () => const ForcePasswordChangeScreen(user: _instrutorUser),
  ),

  // A casca da app, com a barra de separadores — o que mais gente vê.
  // Uma vez por perfil, porque a barra é diferente em cada um e é ela
  // que come altura ao conteúdo.
  _Caso('HomeScreen · Aluno', () => const HomeScreen()),
  _Caso('HomeScreen · Instrutor', () => const HomeScreen(), papeis: _instrutor),
  _Caso('HomeScreen · Gestor', () => const HomeScreen(), papeis: _gestor),

  // Aluno
  _Caso(
    'MemberHomeScreen',
    () => const MemberHomeScreen(memberId: 'member_1'),
    precisaScaffold: true,
  ),
  _Caso('BookTrainingScreen', () => const BookTrainingScreen()),
  _Caso('MyBookingsScreen', () => const MyBookingsScreen()),
  _Caso('MyProfileScreen', () => const MyProfileScreen(memberId: 'member_1')),
  _Caso(
    'MyTrainingPlanScreen',
    () => const MyTrainingPlanScreen(memberId: 'member_1'),
  ),
  _Caso(
    'ActiveWorkoutScreen',
    () => ActiveWorkoutScreen(memberId: 'member_1', session: _treino),
  ),
  _Caso(
      'ExerciseVideoScreen',
      () => const ExerciseVideoScreen(
            exercise: _exercicio,
          )),
  _Caso(
    'FreeTrainingSlotDetailScreen',
    () => FreeTrainingSlotDetailScreen(slot: _slot),
  ),
  _Caso('FreeTrainingScreen', () => const FreeTrainingScreen()),
  _Caso(
    'PaymentHistoryScreen',
    () => const PaymentHistoryScreen(member: _membro),
  ),

  // Instrutor
  _Caso(
    'InstructorHomeScreen',
    () => const InstructorHomeScreen(appUser: _instrutorUser),
    papeis: _instrutor,
    precisaScaffold: true,
  ),
  _Caso(
    'InstructorCalendarScreen',
    () => const InstructorCalendarScreen(),
    papeis: _instrutor,
  ),
  _Caso(
    'OccurrenceDetailScreen',
    () => const OccurrenceDetailScreen(occurrenceId: 'occ_0'),
    papeis: _instrutor,
  ),
  _Caso(
    'GroupWorkoutScreen',
    () => const GroupWorkoutScreen(
      occurrenceId: 'occ_0',
      title: 'Treino Funcional em Grupo · 18:30',
    ),
    papeis: _instrutor,
  ),
  _Caso(
    'LoadEvolutionScreen',
    () => const LoadEvolutionScreen(
      memberId: 'member_1',
      exerciseId: 'ex_1',
      exerciseName: 'Agachamento com Barra Livre',
    ),
    papeis: _instrutor,
  ),
  _Caso(
    'InstructorStudentsScreen',
    () => const InstructorStudentsScreen(),
    papeis: _instrutor,
  ),
  _Caso(
    'AssessmentFormScreen',
    () => const AssessmentFormScreen(member: _membro),
    papeis: _instrutor,
  ),
  _Caso(
    'AssessmentListScreen',
    () => const AssessmentListScreen(member: _membro),
    papeis: _instrutor,
  ),
  _Caso(
    'AssessmentDetailScreen',
    () => AssessmentDetailScreen(member: _membro, assessment: _avaliacao),
    papeis: _instrutor,
  ),
  _Caso(
    'AddPlanEntryScreen',
    () => const AddPlanEntryScreen(
      member: _membro,
      workoutId: 'workout_1',
      nextPosition: 3,
    ),
    papeis: _instrutor,
  ),
  _Caso(
    'StudentTrainingScreen',
    () => const StudentTrainingScreen(member: _membro),
    papeis: _instrutor,
  ),
  _Caso(
    'TrainingPlanEditorScreen',
    () => const TrainingPlanEditorScreen(member: _membro),
    papeis: _instrutor,
  ),
  _Caso(
    'WorkoutHistoryScreen',
    () => const WorkoutHistoryScreen(memberId: 'member_1'),
    papeis: _instrutor,
  ),
  _Caso(
    'SendNotificationScreen',
    () => const SendNotificationScreen(),
    papeis: _instrutor,
  ),

  // Gestor
  _Caso(
    'ManagerScreen',
    () => const ManagerScreen(),
    papeis: _gestor,
    precisaScaffold: true,
  ),
  _Caso(
    'GestorDashboardScreen',
    () => const GestorDashboardScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ManageMembersScreen',
    () => const ManageMembersScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ManagePaymentsScreen',
    () => const ManagePaymentsScreen(),
    papeis: _gestor,
  ),
  _Caso('ManagePlansScreen', () => const ManagePlansScreen(), papeis: _gestor),
  _Caso(
    'ManageServicesScreen',
    () => const ManageServicesScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ManageSeriesScreen',
    () => const ManageSeriesScreen(),
    papeis: _gestor,
  ),
  _Caso('ManageStaffScreen', () => const ManageStaffScreen(), papeis: _gestor),
  _Caso('ManageUsersScreen', () => const ManageUsersScreen(), papeis: _gestor),
  _Caso(
    'ManageModalitiesScreen',
    () => const ManageModalitiesScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ManageExerciseCategoriesScreen',
    () => const ManageExerciseCategoriesScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ManageFreeTrainingScreen',
    () => const ManageFreeTrainingScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ExerciseLibraryScreen',
    () => const ExerciseLibraryScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'ExerciseFormScreen',
    () => const ExerciseFormScreen(),
    papeis: _gestor,
  ),
  _Caso('RetentionScreen', () => const RetentionScreen(), papeis: _gestor),
  _Caso('StudioInfoScreen', () => const StudioInfoScreen(), papeis: _gestor),
  _Caso(
    'TenantSettingsScreen',
    () => const TenantSettingsScreen(),
    papeis: _gestor,
  ),
  _Caso('CreateUserScreen', () => const CreateUserScreen(), papeis: _gestor),
  _Caso(
    'CreateSeriesScreen',
    () => const CreateSeriesScreen(),
    papeis: _gestor,
  ),
  _Caso(
    'MemberDetailScreen',
    () => const MemberDetailScreen(member: _membro),
    papeis: _gestor,
  ),
  _Caso(
    'MemberStatsScreen',
    () => const MemberStatsScreen(member: _membro),
    papeis: _gestor,
  ),
  _Caso(
    'AssignSubscriptionScreen',
    () => const AssignSubscriptionScreen(initialMember: _membro),
    papeis: _gestor,
  ),
  _Caso(
    'SeriesDetailScreen',
    () => SeriesDetailScreen(series: _serie),
    papeis: _gestor,
  ),
  _Caso(
    'StaffDetailScreen',
    () => const StaffDetailScreen(staff: _instrutorStaff),
    papeis: _gestor,
  ),
  _Caso(
    'PlanDetailScreen',
    () => const PlanDetailScreen(plan: _plano),
    papeis: _gestor,
  ),
];
