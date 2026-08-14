import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../core/config/login_identifier.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/role.dart';
import '../../repositories/auth_repository.dart';

/// Códigos do Firebase Auth que, no contexto do UC01, todos significam a
/// mesma coisa para o utilizador: "número de sócio ou password errados".
/// Não distinguimos entre eles na UI de propósito.
const _genericInvalidCredentialCodes = {
  'user-not-found',
  'wrong-password',
  'invalid-credential',
  'invalid-email',
};

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final fb_auth.FirebaseAuth _auth;

  @override
  Stream<AppUser?> authStateChanges() {
    // idTokenChanges (não authStateChanges) porque precisamos de reagir
    // também quando o token é refrescado com novos custom claims (ex:
    // imediatamente a seguir ao login, depois de createMember ter
    // atribuído tenantId/role).
    return _auth.idTokenChanges().asyncMap((user) async {
      if (user == null) return null;

      final tokenResult = await user.getIdTokenResult();
      final tenantId = tokenResult.claims?['tenantId'] as String?;
      final roleClaims = tokenResult.claims?['roles'] as List<dynamic>?;

      if (tenantId == null || roleClaims == null || roleClaims.isEmpty) {
        // Conta autenticada mas sem claims de tenant/role ainda —
        // tratada como sessão não utilizável (ver AuthRepository docs).
        return null;
      }

      return AppUser(
        uid: user.uid,
        tenantId: tenantId,
        roles: roleClaims.map((r) => Role.fromClaim(r as String)).toSet(),
      );
    });
  }

  @override
  Future<void> signInWithMemberNumber({
    required String tenantId,
    required String memberNumber,
    required String password,
  }) async {
    // Fase 3: este era, até agora, só o caminho do Aluno (UC01) — mas a
    // Fase 3 introduziu os primeiros ecrãs que só um Gestor consegue
    // usar, e nunca tinha existido nenhuma forma de um Gestor entrar na
    // app (createStaff.ts usa o email real para login do staff, não um
    // nº gerado — ver comentário nesse ficheiro). Em vez de um segundo
    // ecrã de login, o mesmo campo passa a aceitar as duas coisas: um
    // identificador com '@' é tratado como email real de staff; sem
    // '@', continua a ser um nº de sócio, convertido no email sintético
    // de sempre. Não há ambiguidade possível — nenhum nº de sócio pode
    // conter '@'.
    final identifier = memberNumber.trim();
    final email = identifier.contains('@')
        ? identifier
        : buildSyntheticEmail(tenantId: tenantId, memberNumber: identifier);
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      if (_genericInvalidCredentialCodes.contains(e.code)) {
        throw const InvalidCredentialsException();
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('updatePassword chamado sem sessão ativa.');
    }
    await user.updatePassword(newPassword);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }
}
