import '../../domain/entities/app_user.dart';
import '../../repositories/account_repository.dart';

/// UC22 — troca obrigatória da password temporária no 1º login.
///
/// Era em dois passos do cliente: `AuthRepository.updatePassword` e
/// depois uma escrita direta na flag `passwordTemporaria`. A segunda
/// nunca passava nas Security Rules para Instrutores nem Alunos — só o
/// Gestor tem `allow write` em `staff`/`members` — por isso a password
/// mudava, a flag ficava, e o `AuthGate` repetia o ecrã sem fim.
///
/// As duas passaram para a Cloud Function
/// `completeTemporaryPasswordChange`, onde acontecem do mesmo lado: ou
/// muda tudo ou não muda nada. A ordem (password primeiro, flag
/// depois) e o que fazer quando a password é recusada são agora
/// responsabilidade dela, e estão testados em
/// `firebase/tests/temporary-password.test.ts`.
///
/// Isto fica como costura: os ecrãs continuam a falar com um caso de
/// uso e não com um repositório, e [user] mantém-se na assinatura
/// porque é o ecrã que sabe quem está a trocar — mesmo que hoje o
/// servidor o tire do token.
class CompleteTemporaryPasswordChangeUseCase {
  const CompleteTemporaryPasswordChangeUseCase(this._accountRepository);

  final AccountRepository _accountRepository;

  Future<void> call({
    required AppUser user,
    required String newPassword,
  }) async {
    await _accountRepository.completeTemporaryPasswordChange(newPassword);
  }
}
