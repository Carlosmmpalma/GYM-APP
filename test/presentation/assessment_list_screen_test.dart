import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/plan_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/assessment.dart';
import 'package:gym_saas/domain/entities/consent.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/assessment_list_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

const _tenantId = 'tenant_test';

const _member = MemberSummary(
  uid: 'member_1',
  memberNumber: '000001',
  name: 'Rita Ferreira',
  active: true,
);

/// Fase 11 — "Nova avaliação" vivia no ecrã de CIMA, ao lado dos cartões
/// de navegação. Criar uma avaliação pertence a onde se veem as
/// avaliações.
///
/// Três comportamentos aqui que se partem sem se dar por isso: quem vê o
/// botão, quem não vê, e o caso em que o membro não autorizou dados de
/// saúde — em que o servidor recusaria a escrita de qualquer forma.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Widget buildApp({
    required AppUser appUser,
    required bool healthConsent,
    List<Assessment> assessments = const [],
  }) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
        assessmentsProvider(_member.uid)
            .overrideWith((ref) => Stream.value(assessments)),
        memberProfileProvider(_member.uid).overrideWith(
          (ref) => Stream.value(
            MemberSummary(
              uid: _member.uid,
              memberNumber: _member.memberNumber,
              name: _member.name,
              active: true,
              consent: MemberConsent(
                privacyPolicyVersion: kPrivacyPolicyVersion,
                acceptedAt: DateTime(2026, 8, 1),
                healthDataGranted: healthConsent,
              ),
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: AssessmentListScreen(member: _member)),
    );
  }

  testWidgets('um Instrutor pode criar a partir da própria lista',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        appUser: const AppUser(
            uid: 'staff_1', tenantId: _tenantId, roles: {Role.instructor}),
        healthConsent: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nova avaliação'), findsOneWidget);
  });

  testWidgets('um Gestor também', (tester) async {
    await tester.pumpWidget(
      buildApp(
        appUser: const AppUser(
            uid: 'staff_1', tenantId: _tenantId, roles: {Role.manager}),
        healthConsent: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nova avaliação'), findsOneWidget);
  });

  testWidgets('o próprio Aluno lê o histórico mas NÃO cria', (tester) async {
    // Um aluno não se avalia a si próprio, e as Security Rules recusam
    // a escrita. O botão nunca lhe deve aparecer.
    await tester.pumpWidget(
      buildApp(
        appUser: const AppUser(
            uid: 'member_1', tenantId: _tenantId, roles: {Role.member}),
        healthConsent: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nova avaliação'), findsNothing);
    expect(find.text('Fazer a primeira avaliação'), findsNothing);
  });

  testWidgets('sem consentimento de dados de saúde, explica em vez de oferecer',
      (tester) async {
    // O servidor recusa escrever uma avaliação sem o consentimento do
    // membro (RGPD, artigo 9.º). Mostrar o botão seria oferecer um
    // caminho que termina numa recusa.
    await tester.pumpWidget(
      buildApp(
        appUser: const AppUser(
            uid: 'staff_1', tenantId: _tenantId, roles: {Role.instructor}),
        healthConsent: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem autorização para avaliações'), findsOneWidget);
    expect(find.textContaining('Rita Ferreira'), findsOneWidget);
    expect(find.text('Nova avaliação'), findsNothing);
  });

  testWidgets('lista vazia com permissão convida a fazer a primeira',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        appUser: const AppUser(
            uid: 'staff_1', tenantId: _tenantId, roles: {Role.instructor}),
        healthConsent: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fazer a primeira avaliação'), findsOneWidget);
  });
}
