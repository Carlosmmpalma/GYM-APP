import '../domain/entities/app_user.dart';

/// Acesso aos campos do documento members/staff que a Fase 1 precisa de
/// conhecer — hoje, só a flag de password temporária (UC22). O resto do
/// documento (nome, contactos, etc.) pertence a repositories futuros
/// (Fase 3+), para não acoplar este repository a todo o perfil do
/// membro antes de existir ecrã que precise disso.
abstract class AccountRepository {
  Future<bool> hasTemporaryPassword(AppUser user);

  Future<void> clearTemporaryPasswordFlag(AppUser user);
}
