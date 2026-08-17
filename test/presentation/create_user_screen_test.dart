import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/admin_providers.dart';
import 'package:gym_saas/domain/entities/new_account_credentials.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/create_user_screen.dart';
import 'package:gym_saas/repositories/user_provisioning_repository.dart';

/// Pedido pelo Carlo depois de testar "Criar utilizador": provar que
/// os novos campos pessoais (telefone/email/data de
/// nascimento/morada/NIF/contacto de emergência) chegam mesmo ao
/// repository, não só que aparecem no formulário.
class _FakeUserProvisioningRepository implements UserProvisioningRepository {
  ({
    String name,
    String phone,
    String email,
    DateTime? birthDate,
    String address,
    String nif,
    String emergencyContact,
  })? lastCreateMemberCall;

  @override
  Future<NewAccountCredentials> createMember({
    required String name,
    String phone = '',
    String email = '',
    DateTime? birthDate,
    String address = '',
    String nif = '',
    String emergencyContact = '',
  }) async {
    lastCreateMemberCall = (
      name: name,
      phone: phone,
      email: email,
      birthDate: birthDate,
      address: address,
      nif: nif,
      emergencyContact: emergencyContact,
    );
    return const NewAccountCredentials(
      uid: 'member_1',
      loginIdentifier: '000001',
      temporaryPassword: 'TempPass123!',
    );
  }

  @override
  Future<NewAccountCredentials> createStaff({
    required String name,
    required String email,
    required Set<Role> roles,
    Set<String> modalityIds = const {},
    String phone = '',
    DateTime? birthDate,
    String address = '',
    String nif = '',
    String emergencyContact = '',
  }) async =>
      throw UnimplementedError();
}

void main() {
  Widget buildApp(_FakeUserProvisioningRepository repository) {
    return ProviderScope(
      overrides: [
        userProvisioningRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: CreateUserScreen()),
    );
  }

  testWidgets('criar um Aluno envia telefone/email/NIF/morada ao repository',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeUserProvisioningRepository();
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome completo'),
      'Rita Ferreira',
    );
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Telefone'), '912345678');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Morada'), 'Rua Nova 12');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'NIF'), '123456789');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email de contacto'),
      'rita@example.com',
    );

    await tester.tap(find.text('Criar e gerar credenciais'));
    await tester.pumpAndSettle();

    // Diálogo de credenciais (bloqueante) aparece — confirma e fecha.
    expect(find.text('Conta criada'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    expect(repository.lastCreateMemberCall?.name, 'Rita Ferreira');
    expect(repository.lastCreateMemberCall?.phone, '912345678');
    expect(repository.lastCreateMemberCall?.address, 'Rua Nova 12');
    expect(repository.lastCreateMemberCall?.nif, '123456789');
    expect(repository.lastCreateMemberCall?.email, 'rita@example.com');
  });
}
