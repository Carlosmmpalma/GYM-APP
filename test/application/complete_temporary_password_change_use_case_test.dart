import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/complete_temporary_password_change_use_case.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/repositories/account_repository.dart';
import 'package:gym_saas/repositories/auth_repository.dart';

class _FakeAuthRepository implements AuthRepository {
  String? updatedPassword;
  bool throwOnUpdate = false;

  @override
  Future<void> updatePassword(String newPassword) async {
    if (throwOnUpdate) {
      throw Exception('password fraca');
    }
    updatedPassword = newPassword;
  }

  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> signInWithMemberNumber({
    required String tenantId,
    required String memberNumber,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeAccountRepository implements AccountRepository {
  bool flagCleared = false;

  @override
  Future<bool> hasTemporaryPassword(AppUser user) async => !flagCleared;

  @override
  Future<void> clearTemporaryPasswordFlag(AppUser user) async {
    flagCleared = true;
  }
}

void main() {
  const user = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});

  test('atualiza a password e só depois limpa a flag', () async {
    final authRepo = _FakeAuthRepository();
    final accountRepo = _FakeAccountRepository();
    final useCase =
        CompleteTemporaryPasswordChangeUseCase(authRepo, accountRepo);

    await useCase(user: user, newPassword: 'novaPassword123');

    expect(authRepo.updatedPassword, 'novaPassword123');
    expect(accountRepo.flagCleared, isTrue);
  });

  test('se a atualização da password falhar, a flag NÃO é limpa', () async {
    final authRepo = _FakeAuthRepository()..throwOnUpdate = true;
    final accountRepo = _FakeAccountRepository();
    final useCase =
        CompleteTemporaryPasswordChangeUseCase(authRepo, accountRepo);

    await expectLater(
      () => useCase(user: user, newPassword: 'x'),
      throwsException,
    );
    expect(accountRepo.flagCleared, isFalse);
  });
}
