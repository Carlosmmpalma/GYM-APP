import '../../repositories/auth_repository.dart';

class SignInWithMemberNumberUseCase {
  const SignInWithMemberNumberUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<void> call({
    required String tenantId,
    required String memberNumber,
    required String password,
  }) {
    return _authRepository.signInWithMemberNumber(
      tenantId: tenantId,
      memberNumber: memberNumber,
      password: password,
    );
  }
}
