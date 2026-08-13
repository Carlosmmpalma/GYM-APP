import '../../domain/entities/app_user.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/auth_repository.dart';

/// UC22 — troca obrigatória da password temporária no 1º login. Só
/// depois de o Firebase Auth aceitar a nova password é que limpamos a
/// flag `passwordTemporaria` no Firestore — se a alteração falhar (ex:
/// password demasiado fraca), a flag continua true e o utilizador
/// continua a ser forçado pelo AuthGate a repetir o ecrã.
class CompleteTemporaryPasswordChangeUseCase {
  const CompleteTemporaryPasswordChangeUseCase(
    this._authRepository,
    this._accountRepository,
  );

  final AuthRepository _authRepository;
  final AccountRepository _accountRepository;

  Future<void> call({
    required AppUser user,
    required String newPassword,
  }) async {
    await _authRepository.updatePassword(newPassword);
    await _accountRepository.clearTemporaryPasswordFlag(user);
  }
}
