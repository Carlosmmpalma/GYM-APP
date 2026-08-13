import 'package:equatable/equatable.dart';

/// UC22 — resultado de criar uma conta nova (Aluno via `createMember`,
/// Staff via `createStaff`). O mockup ("Criar utilizador — Aluno") é
/// explícito: "Credenciais comunicadas ao utilizador fora da app (ex:
/// presencialmente)" — por isso o ecrã que usa isto tem de MOSTRAR a
/// password temporária uma única vez, não só confirmar sucesso.
class NewAccountCredentials extends Equatable {
  const NewAccountCredentials({
    required this.uid,
    required this.loginIdentifier,
    required this.temporaryPassword,
  });

  final String uid;

  /// Nº de sócio (Aluno) ou email (Staff) — o que a pessoa usa para
  /// entrar (ver o mesmo campo dual em `login_screen.dart`).
  final String loginIdentifier;
  final String temporaryPassword;

  @override
  List<Object?> get props => [uid, loginIdentifier, temporaryPassword];
}
