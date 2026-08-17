import '../domain/entities/new_account_credentials.dart';
import '../domain/entities/role.dart';

/// UC22 — gap encontrado a comparar com os mockups: `createMember`/
/// `createStaff` (Cloud Functions, Fase 1) nunca tinham sido ligadas a
/// nenhum ecrã da app — só o seed script as chamava. Esta interface é
/// a fronteira para o `CreateUserScreen` novo.
abstract class UserProvisioningRepository {
  /// UC22 — cria um Aluno. Nº de sócio gerado automaticamente do lado
  /// da Cloud Function (nunca escrito pelo Gestor). Os dados pessoais
  /// são todos opcionais — pedido pelo Carlo depois de testar este
  /// ecrã: continuam a poder ser preenchidos depois em
  /// `MemberDetailScreen` (`updateMemberProfile`), não é preciso tê-los
  /// todos à mão no momento da criação.
  Future<NewAccountCredentials> createMember({
    required String name,
    String phone = '',
    String email = '',
    DateTime? birthDate,
    String address = '',
    String nif = '',
    String emergencyContact = '',
  });

  /// UC22 — cria staff (Instrutor e/ou Gestor). Ao contrário do Aluno,
  /// staff usa o email real para login (decisão fechada — ver
  /// `createStaff.ts`). [roles] não pode estar vazio (mesma validação
  /// do schema zod do lado do servidor, repetida aqui só para dar erro
  /// cedo na UI). Mesmos dados pessoais opcionais do Aluno.
  Future<NewAccountCredentials> createStaff({
    required String name,
    required String email,
    required Set<Role> roles,
    Set<String> modalityIds = const {},
    String phone = '',
    DateTime? birthDate,
    String address = '',
    String nif = '',
    String emergencyContact = '',
  });
}
