import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/sign_in_with_member_number_use_case.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/repositories/auth_repository.dart';

class _FakeAuthRepository implements AuthRepository {
  String? lastTenantId;
  String? lastMemberNumber;
  String? lastPassword;
  bool throwInvalidCredentials = false;

  @override
  Future<void> signInWithMemberNumber({
    required String tenantId,
    required String memberNumber,
    required String password,
  }) async {
    lastTenantId = tenantId;
    lastMemberNumber = memberNumber;
    lastPassword = password;
    if (throwInvalidCredentials) {
      throw const InvalidCredentialsException();
    }
  }

  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String newPassword) async {}
}

void main() {
  test('passa os parâmetros tal como recebidos ao repository', () async {
    final repo = _FakeAuthRepository();
    final useCase = SignInWithMemberNumberUseCase(repo);

    await useCase(
      tenantId: 'nxt_performance_studio',
      memberNumber: '000123',
      password: 'segredo123',
    );

    expect(repo.lastTenantId, 'nxt_performance_studio');
    expect(repo.lastMemberNumber, '000123');
    expect(repo.lastPassword, 'segredo123');
  });

  test('propaga InvalidCredentialsException sem a transformar', () async {
    final repo = _FakeAuthRepository()..throwInvalidCredentials = true;
    final useCase = SignInWithMemberNumberUseCase(repo);

    expect(
      () => useCase(tenantId: 't', memberNumber: '1', password: 'x'),
      throwsA(isA<InvalidCredentialsException>()),
    );
  });
}
