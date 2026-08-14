import '../domain/entities/app_user.dart';

/// Fronteira de autenticação. A camada acima nunca importa `firebase_auth`
/// diretamente — só esta interface e o [AppUser] que ela devolve
/// (Platform Foundation §11).
abstract class AuthRepository {
  /// Emite o [AppUser] resolvido (uid + tenantId + roles a partir dos
  /// custom claims) sempre que o estado de autenticação muda, ou `null`
  /// quando não há sessão. Emite também `null` se o utilizador estiver
  /// autenticado mas os claims ainda não tiverem `tenantId`/`role`
  /// atribuídos (conta a meio de criação) — nesse caso trata-se como
  /// "não utilizável" em vez de deixar a app num estado inconsistente.
  Stream<AppUser?> authStateChanges();

  /// UC01: login por número de sócio, não por email — para Alunos. A
  /// implementação concreta é responsável por transformar `memberNumber`
  /// num identificador aceite pelo Firebase Auth.
  ///
  /// Fase 3: o mesmo parâmetro também aceita o email real de staff
  /// (Gestor/Instrutor) — se contiver '@', é usado tal como está, sem
  /// nenhuma transformação. Ver nota em `firebase_auth_repository.dart`.
  /// O nome do método/parâmetro ficou por mudar para não gerar diffs
  /// maiores do que o necessário; pensa nele como "identificador de
  /// login", não literalmente "só número de sócio".
  ///
  /// Lança [InvalidCredentialsException] tanto para identificador
  /// inexistente como para password errada — nunca revela qual dos dois
  /// falhou (UC01: "mensagem genérica de erro").
  Future<void> signInWithMemberNumber({
    required String tenantId,
    required String memberNumber,
    required String password,
  });

  Future<void> signOut();

  /// UC22 — troca obrigatória da password temporária no 1º login.
  /// Só altera a credencial no Firebase Auth; quem limpa a flag
  /// `password_temporaria` no documento do membro/staff é a camada de
  /// aplicação, depois disto ter sucesso.
  Future<void> updatePassword(String newPassword);

  /// UC01-A — só faz sentido para staff (email real): o Firebase Auth
  /// envia o link de reset diretamente para essa caixa de correio, sem
  /// precisar de nenhuma Cloud Function nova. Para membros (email
  /// sintético, nunca entregável) isto NÃO é chamado — `LoginScreen`
  /// intercepta antes, ver nota lá.
  Future<void> sendPasswordResetEmail(String email);
}

class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();

  @override
  String toString() => 'Número de sócio ou password inválidos.';
}
