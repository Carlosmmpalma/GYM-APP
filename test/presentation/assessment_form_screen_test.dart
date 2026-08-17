import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/application/providers/training_providers.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/assessment.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/assessment_form_screen.dart';
import 'package:gym_saas/repositories/assessment_repository.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';
const _staffId = 'staff_1';

class _FakeAssessmentRepository implements AssessmentRepository {
  Map<String, dynamic>? lastCreateCall;

  @override
  Stream<List<Assessment>> watchAssessments(String memberId) =>
      const Stream.empty();

  @override
  Future<String> createAssessment({
    required String memberId,
    required String instructorId,
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  }) async {
    lastCreateCall = {
      'memberId': memberId,
      'instructorId': instructorId,
      'idade': idade,
      'peso': peso,
      'altura': altura,
      'percentMassaGorda': percentMassaGorda,
      'massaMuscular': massaMuscular,
      'gorduraVisceral': gorduraVisceral,
      'metabolismoBasal': metabolismoBasal,
      'percentAgua': percentAgua,
      'idadeMetabolica': idadeMetabolica,
      'pressaoArterial': pressaoArterial,
      'perimetroCintura': perimetroCintura,
      'perimetroAbdominal': perimetroAbdominal,
      'forcaMS': forcaMS,
      'forcaMI': forcaMI,
      'forcaCore': forcaCore,
      'flexibilidade': flexibilidade,
      'resistencia': resistencia,
    };
    return 'assessment_1';
  }

  @override
  Future<void> updateAssessment({
    required String memberId,
    required String assessmentId,
    required String updatedBy,
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  }) =>
      throw UnimplementedError();
}

void main() {
  const member = MemberSummary(
    uid: _memberId,
    memberNumber: '000001',
    name: 'Rita Ferreira',
    active: true,
  );

  Widget buildApp(_FakeAssessmentRepository repository) {
    return ProviderScope(
      overrides: [
        assessmentRepositoryProvider.overrideWithValue(repository),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
                uid: _staffId, tenantId: _tenantId, roles: {Role.instructor}),
          ),
        ),
      ],
      // `currentAppUserProvider` já está sempre resolvido por esta
      // altura na app real (AuthGate/HomeScreen lêem-no primeiro) —
      // este `Consumer` reproduz isso, para `_save()` (que faz
      // `ref.read`, não `ref.watch`) não apanhar o provider ainda em
      // `AsyncLoading` no primeiro toque (mesma armadilha já
      // documentada em `occurrence_detail_screen_test.dart`).
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(currentAppUserProvider);
            return const AssessmentFormScreen(member: member);
          },
        ),
      ),
    );
  }

  testWidgets(
      'campos obrigatórios em falta bloqueiam a gravação (mockup: '
      '"campos obrigatórios em falta bloqueiam a gravação")', (tester) async {
    // 17 campos num único ListView — bem para lá da viewport de teste
    // por omissão (800x600); sem isto o SliverList nem chega a
    // construir "Guardar avaliação" (mesma armadilha já documentada em
    // member_detail_screen_test.dart).
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeAssessmentRepository();
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar avaliação'));
    await tester.pumpAndSettle();

    expect(repository.lastCreateCall, isNull);
    expect(find.text('Obrigatório'), findsWidgets);
  });

  testWidgets('preenchido corretamente, calcula o IMC e cria a avaliação',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeAssessmentRepository();
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    Future<void> fill(String label, String value) async {
      await tester.enterText(find.widgetWithText(TextFormField, label), value);
    }

    await fill('Idade', '30');
    await fill('Peso (kg)', '70');
    await fill('Altura (m)', '1.75');
    await tester.pump();

    // IMC = 70 / 1.75² = 22.9 — pré-visualização de leitura, nunca um
    // campo de input.
    expect(find.text('22.9'), findsOneWidget);

    await fill('% Massa Gorda', '20');
    await fill('Massa Muscular (kg)', '30');
    await fill('Gordura Visceral', '8');
    await fill('Metabolismo Basal (kcal)', '1600');
    await fill('% Água', '55');
    await fill('Idade Metabólica', '28');
    await fill('Pressão Arterial', '112/72');
    await fill('Perímetro Cintura (cm)', '80');
    await fill('Perímetro Abdominal (cm)', '85');

    await tester.tap(find.text('Guardar avaliação'));
    await tester.pumpAndSettle();

    expect(repository.lastCreateCall?['memberId'], _memberId);
    expect(repository.lastCreateCall?['instructorId'], _staffId);
    expect(repository.lastCreateCall?['idade'], 30);
    expect(repository.lastCreateCall?['peso'], 70.0);
    expect(repository.lastCreateCall?['pressaoArterial'], '112/72');
    // Físicos têm um valor por omissão (primeiro dropdown) — não
    // bloqueiam a gravação mesmo sem serem tocados.
    expect(repository.lastCreateCall?['forcaMS'], isNotEmpty);
  });
}
