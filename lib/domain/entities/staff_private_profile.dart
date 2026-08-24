import 'package:equatable/equatable.dart';

/// Os dados pessoais de um membro do staff.
///
/// Vivem em `tenants/{t}/staff/{uid}/private/profile`, e não no
/// documento de staff, porque esse é legível por **todo o tenant** —
/// é de lá que sai o nome do instrutor no cartão de uma aula, que
/// qualquer aluno vê. Com estes campos lá dentro, qualquer aluno
/// conseguia ler o NIF e a morada dos instrutores; é a mesma fuga que
/// foi fechada em `members` na Fase 11, e o staff tinha ficado para
/// trás.
///
/// Só o próprio e o Gestor conseguem ler isto (Security Rules), e a
/// escrita passa sempre por `createStaff`/`updateStaffProfile`.
class StaffPrivateProfile extends Equatable {
  const StaffPrivateProfile({
    this.phone = '',
    this.birthDate,
    this.address = '',
    this.nif = '',
    this.emergencyContact = '',
  });

  /// O que se mostra enquanto ainda não chegou nada do servidor — e
  /// também o que um Instrutor vê da ficha de outro, porque nesse caso
  /// a leitura é recusada e não há nada a mostrar.
  static const empty = StaffPrivateProfile();

  final String phone;
  final DateTime? birthDate;
  final String address;
  final String nif;
  final String emergencyContact;

  @override
  List<Object?> get props => [phone, birthDate, address, nif, emergencyContact];
}
