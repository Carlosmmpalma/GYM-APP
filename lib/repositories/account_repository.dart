import '../domain/entities/app_user.dart';

/// Acesso aos campos do documento members/staff que a Fase 1 precisa de
/// conhecer — hoje, só a flag de password temporária (UC22). O resto do
/// documento (nome, contactos, etc.) pertence a repositories futuros
/// (Fase 3+), para não acoplar este repository a todo o perfil do
/// membro antes de existir ecrã que precise disso.
abstract class AccountRepository {
  Future<bool> hasTemporaryPassword(AppUser user);

  /// Define a password definitiva E limpa a flag, de uma vez.
  ///
  /// Era em dois passos do cliente — `updatePassword` no Auth, depois
  /// uma escrita direta na flag — e a segunda nunca passava nas Rules
  /// para Instrutores e Alunos: só o Gestor tem `allow write` nos
  /// documentos de `staff`/`members`. A password mudava, a flag ficava,
  /// e o AuthGate repetia o ecrã para sempre.
  ///
  /// Juntas numa Cloud Function, ou mudam as duas ou não muda nenhuma —
  /// e a flag deixa de ser escrevível pelo cliente, que é o que impede
  /// alguém de a pôr a `false` e saltar a troca obrigatória (UC22).
  Future<void> completeTemporaryPasswordChange(String newPassword);
}
