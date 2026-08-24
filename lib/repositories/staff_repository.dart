import '../domain/entities/staff_private_profile.dart';
import '../domain/entities/staff_summary.dart';

/// Gap encontrado a comparar com `Functional/nxt-studio-screens.html`:
/// nunca existiu nenhum repository para staff no Flutter, só
/// `MemberRepository`. `createStaff.ts` (Fase 1) escreve o documento;
/// isto é só a leitura/gestão do lado da app.
abstract class StaffRepository {
  Stream<List<StaffSummary>> watchStaff();

  /// Os dados pessoais de um membro do staff. Só o próprio e o Gestor
  /// os conseguem ler — ver [StaffPrivateProfile] e as Security Rules.
  /// A quem não pode, o stream devolve [StaffPrivateProfile.empty] em
  /// vez de rebentar: a ficha abre na mesma, só sem esses campos.
  Stream<StaffPrivateProfile> watchPrivateProfile(String staffId);

  /// Desativar, nunca eliminar — mesmo padrão de
  /// `MemberRepository.setMemberActive`. Note: quando `staffId` tem
  /// `Role.instructor` e `active == false`, quem chama isto (UI) deve
  /// preferir `deactivateInstructor` (Cloud Function, cascata de
  /// UC24) — ver `staff_detail_screen.dart`. Este método fica só a
  /// escrita simples, sem cascata nenhuma.
  Future<void> setStaffActive({
    required String staffId,
    required bool active,
  });

  /// Fase 6 (UC12/22 fechado) — edita as modalidades de um instrutor.
  Future<void> setModalityIds({
    required String staffId,
    required Set<String> modalityIds,
  });

  /// Fase 11 — os serviços que este instrutor pode lecionar.
  ///
  /// Ao contrário das modalidades, que são descritivas, isto **autoriza**:
  /// as Security Rules só deixam um instrutor criar aulas dos serviços
  /// que constam aqui.
  Future<void> setStaffServices({
    required String staffId,
    required Set<String> serviceIds,
  });

  /// UC24 — desativa um instrutor E cancela em cadeia as suas séries/
  /// ocorrências futuras (Cloud Function `deactivateInstructor`,
  /// Admin SDK — precisa de percorrer séries + ocorrências + bookings
  /// de cada uma, não dá para exprimir em Security Rules). Devolve um
  /// resumo (quantas séries/ocorrências/bookings foram afetados) para
  /// a UI poder confirmar ao Gestor o que realmente aconteceu.
  Future<
      ({
        int seriesCancelled,
        int occurrencesCancelled,
        int bookingsCancelled
      })> deactivateInstructorWithCascade(String staffId);

  /// Fase 6 (UC21) — mesmo padrão de `MemberRepository.registerFcmToken`.
  /// `staff/{id}` continua com escrita ampla no tenant (nunca ganhou a
  /// restrição de `affectedKeys` que `members` tem desde a Fase 5), por
  /// isso não precisa de nenhuma alteração às Security Rules.
  Future<void> registerFcmToken({
    required String staffId,
    required String token,
  });

  /// Pedido pelo Carlo depois de testar "Criar utilizador" — edita
  /// nome/email/dados pessoais de um staff (`StaffDetailScreen`).
  /// Cloud Function `updateStaffProfile` (Admin SDK), ao contrário de
  /// [MemberRepository.updateMemberProfile]: aqui `email` É o login
  /// real (Firebase Auth), por isso mudá-lo tem de sincronizar a
  /// credencial, não só o Firestore — ver nota de arquitetura em
  /// `updateStaffProfile.ts`. Lança se o email novo já pertencer a
  /// outra conta.
  Future<void> updateStaffProfile({
    required String staffId,
    required String name,
    required String email,
    required String phone,
    DateTime? birthDate,
    required String address,
    required String nif,
    required String emergencyContact,
  });
}
