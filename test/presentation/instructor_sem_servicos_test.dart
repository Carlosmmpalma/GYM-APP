import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/admin_providers.dart';
import 'package:gym_saas/application/providers/plan_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/staff_summary.dart';
import 'package:gym_saas/presentation/screens/instructor_students_screen.dart';

/// O ecrã "Alunos" do Instrutor, quando a lista vem vazia.
///
/// Reportado em produção: o estúdio tinha 79 alunos ativos, todos com
/// subscrição ativa, e o Instrutor via "Sem alunos ativos". Duas
/// pessoas foram ao Firestore confirmar que os dados lá estavam — e
/// estavam. O que faltava era o âmbito: `serviceIds` vazio no documento
/// do staff faz `visibleMembersProvider` devolver sempre lista vazia.
///
/// A lista vazia tem portanto DUAS causas, e o ecrã dizia sempre a
/// mesma coisa. A diferença é tudo: numa não há nada a fazer, na outra
/// falta o Gestor atribuir serviços.

const _uidInstrutor = 'instrutor_1';

StaffSummary _instrutor({required Set<String> servicos}) => StaffSummary(
      uid: _uidInstrutor,
      name: 'Ana Marques',
      email: 'ana@estudio.test',
      roles: const {Role.instructor},
      active: true,
      serviceIds: servicos,
    );

const _alunos = [
  MemberSummary(
    uid: 'membro_1',
    memberNumber: '000001',
    name: 'Rita Ferreira',
    active: true,
  ),
];

Widget _app({
  required Set<String> servicosDoInstrutor,
  required List<MemberSummary> visiveis,
  bool gestor = false,
}) {
  return ProviderScope(
    overrides: [
      currentAppUserProvider.overrideWith(
        (ref) => Stream.value(
          AppUser(
            uid: _uidInstrutor,
            tenantId: 'tenant_test',
            roles: {gestor ? Role.manager : Role.instructor},
          ),
        ),
      ),
      staffProvider.overrideWith(
        (ref) => Stream.value([_instrutor(servicos: servicosDoInstrutor)]),
      ),
      visibleMembersProvider.overrideWith((ref) => Stream.value(visiveis)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const InstructorStudentsScreen(),
    ),
  );
}

void main() {
  testWidgets('sem serviços atribuídos, diz o que se passa e a quem pedir',
      (tester) async {
    await tester.pumpWidget(
      _app(servicosDoInstrutor: const {}, visiveis: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem serviços atribuídos'), findsOneWidget);
    expect(find.textContaining('Gestão › Equipa'), findsOneWidget);

    // E sobretudo NÃO diz que não há alunos, porque há.
    expect(find.text('Sem alunos ativos'), findsNothing);
  });

  testWidgets('com serviços mas sem alunos, continua a dizer sem alunos',
      (tester) async {
    // O contraponto. Sem este, bastava trocar uma mensagem pela outra
    // para o teste de cima passar — e o estúdio genuinamente vazio
    // passaria a receber um conselho que não se aplica.
    await tester.pumpWidget(
      _app(servicosDoInstrutor: const {'svc_1'}, visiveis: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem alunos ativos'), findsOneWidget);
    expect(find.text('Sem serviços atribuídos'), findsNothing);
  });

  testWidgets('com alunos, nenhuma das duas mensagens aparece', (tester) async {
    await tester.pumpWidget(
      _app(servicosDoInstrutor: const {'svc_1'}, visiveis: _alunos),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rita Ferreira'), findsOneWidget);
    expect(find.text('Sem serviços atribuídos'), findsNothing);
    expect(find.text('Sem alunos ativos'), findsNothing);
  });
}
