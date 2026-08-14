import '../domain/entities/new_account_credentials.dart';
import '../domain/entities/role.dart';

/// UC22 — gap encontrado a comparar com os mockups: `createMember`/
/// `createStaff` (Cloud Functions, Fase 1) nunca tinham sido ligadas a
/// nenhum ecrã da app — só o seed script as chamava. Esta interface é
/// a fronteira para o `CreateUserScreen` novo.
abstract class UserProvisioningRepository {
  /// UC22 — cria um Aluno. Nº de sócio gerado automaticamente do lado
  /// da Cloud Function (nunca escrito pelo Gestor).
  Future<NewAccountCredentials> createMember({required String name});

  /// UC22 — cria staff (Instrutor e/ou Gestor). Ao contrário do Aluno,
  /// staff usa o email real para login (decisão fechada — ver
  /// `createStaff.ts`). [roles] não pode estar vazio (mesma validação
  /// do schema zod do lado do servidor, repetida aqui só para dar erro
  /// cedo na UI).
  Future<NewAccountCredentials> createStaff({
    required String name,
    required String email,
    required Set<Role> roles,
    Set<String> modalityIds = const {},
  });
}
