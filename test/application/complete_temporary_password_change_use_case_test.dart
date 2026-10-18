import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/use_cases/complete_temporary_password_change_use_case.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/repositories/account_repository.dart';

/// Este teste já verificou duas coisas que deixaram de ser verdade: que
/// o caso de uso mudava a password e SÓ DEPOIS limpava a flag, e que se
/// a password fosse recusada a flag não era tocada.
///
/// Esses dois passos eram ambos do cliente, e o segundo nunca passava
/// nas Security Rules para Instrutores e Alunos. Passaram para a Cloud
/// Function `completeTemporaryPasswordChange`, e é lá que a ordem e o
/// que acontece quando a password é recusada estão testados, contra o
/// emulador — ver `firebase/tests/temporary-password.test.ts`.
///
/// O que sobra aqui é a costura: o ecrã chama o caso de uso, e o caso
/// de uso leva a password ao repositório sem lhe mexer.

class _ContaFalsa implements AccountRepository {
  String? passwordRecebida;
  int chamadas = 0;
  bool rebenta = false;

  @override
  Future<bool> hasTemporaryPassword(AppUser user) async =>
      passwordRecebida == null;

  @override
  Future<void> completeTemporaryPasswordChange(String newPassword) async {
    chamadas += 1;
    if (rebenta) throw Exception('password recusada pelo servidor');
    passwordRecebida = newPassword;
  }
}

void main() {
  const user = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});

  test('leva a password ao repositório, tal e qual', () async {
    final conta = _ContaFalsa();
    final useCase = CompleteTemporaryPasswordChangeUseCase(conta);

    await useCase(user: user, newPassword: 'novaPassword123');

    expect(conta.passwordRecebida, 'novaPassword123');
    expect(conta.chamadas, 1);
  });

  test('o erro do servidor sobe até ao ecrã, não é engolido', () async {
    // O ecrã apanha-o e mostra-o. Se este caso de uso o engolisse, a
    // pessoa via o botão parar de rodar e mais nada — que é
    // indistinguível de ter corrido bem, num ecrã de onde ela não sai.
    final conta = _ContaFalsa()..rebenta = true;
    final useCase = CompleteTemporaryPasswordChangeUseCase(conta);

    await expectLater(
      () => useCase(user: user, newPassword: 'x'),
      throwsException,
    );
    expect(conta.passwordRecebida, isNull);
  });
}
