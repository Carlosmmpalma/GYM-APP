import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/admin_providers.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/domain/entities/staff_summary.dart';
import 'package:gym_saas/presentation/screens/staff_detail_screen.dart';
import 'package:gym_saas/repositories/staff_repository.dart';

/// `updateStaffProfile` passa pela Cloud Function `updateStaffProfile`
/// (sincroniza Firestore + Firebase Auth — ver nota de arquitetura no
/// próprio ficheiro). Mockar `cloud_functions` diretamente exigiria
/// confirmar a forma exata de `HttpsCallableResult` sem correr Flutter
/// a sério (mesmo risco já documentado no README para outros ecrãs) —
/// em vez disso, um fake do repository regista a última chamada, mesmo
/// padrão já usado nos testes de booking desde a Fase 4.
class _FakeStaffRepository implements StaffRepository {
  _FakeStaffRepository(this.initialStaff);

  StaffSummary initialStaff;
  ({
    String staffId,
    String name,
    String email,
    String phone,
    DateTime? birthDate,
    String address,
    String nif,
    String emergencyContact,
  })? lastUpdateStaffProfileCall;

  @override
  Stream<List<StaffSummary>> watchStaff() => Stream.value([initialStaff]);

  @override
  Future<void> setStaffActive(
      {required String staffId, required bool active}) async {}

  @override
  Future<void> setModalityIds({
    required String staffId,
    required Set<String> modalityIds,
  }) async {}

  @override
  Future<
      ({
        int seriesCancelled,
        int occurrencesCancelled,
        int bookingsCancelled
      })> deactivateInstructorWithCascade(
          String staffId) async =>
      (seriesCancelled: 0, occurrencesCancelled: 0, bookingsCancelled: 0);

  @override
  Future<void> registerFcmToken(
      {required String staffId, required String token}) async {}

  @override
  Future<void> updateStaffProfile({
    required String staffId,
    required String name,
    required String email,
    required String phone,
    DateTime? birthDate,
    required String address,
    required String nif,
    required String emergencyContact,
  }) async {
    lastUpdateStaffProfileCall = (
      staffId: staffId,
      name: name,
      email: email,
      phone: phone,
      birthDate: birthDate,
      address: address,
      nif: nif,
      emergencyContact: emergencyContact,
    );
  }
}

void main() {
  const staff = StaffSummary(
    uid: 'staff_1',
    name: 'João Martins',
    email: 'joao@example.com',
    roles: {Role.instructor},
    active: true,
  );

  Widget buildApp(_FakeStaffRepository repository) {
    return ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        staffRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: StaffDetailScreen(staff: staff)),
    );
  }

  testWidgets('mostra os dados pessoais do staff', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(_FakeStaffRepository(staff)));
    await tester.pumpAndSettle();

    expect(find.text('Dados pessoais'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Nome completo'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email (usado para login)'),
        findsOneWidget);
  });

  testWidgets('editar e guardar chama updateStaffProfile com os novos valores',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeStaffRepository(staff);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Telefone'), '912345678');
    await tester.tap(find.text('Guardar dados'));
    await tester.pumpAndSettle();

    expect(repository.lastUpdateStaffProfileCall?.staffId, 'staff_1');
    expect(repository.lastUpdateStaffProfileCall?.phone, '912345678');
    expect(repository.lastUpdateStaffProfileCall?.email, 'joao@example.com');
  });
}
