import 'package:equatable/equatable.dart';

import 'consent.dart';
import 'payment_record.dart';

/// Perfil mínimo de um membro, para listas/pickers de gestão (Fase 3 —
/// ecrã "atribuir plano a um membro"). Não é o [AppUser] (que
/// representa a identidade autenticada + custom claims) — este é o
/// próprio documento `tenants/{tenantId}/members/{uid}`, tal como a
/// Fase 1 o criou (Cloud Function `createMember`). Ver nota em
/// `account_repository.dart`: o perfil completo do membro (contactos,
/// avaliações, etc.) fica para quando existir um ecrã que precise de
/// mais do que isto.
class MemberSummary extends Equatable {
  const MemberSummary({
    required this.uid,
    required this.memberNumber,
    required this.name,
    required this.active,
    this.phone = '',
    this.email = '',
    this.birthDate,
    this.address = '',
    this.nif = '',
    this.emergencyContact = '',
    this.currentPaymentStatus,
    this.currentPaymentPeriod,
    this.consent = const MemberConsent(),
    this.photoPath,
    this.photoUrl,
    this.photoUpdatedAt,
  });

  /// Caminho no Storage da foto de perfil, já reduzida.
  ///
  /// Escrito pela Cloud Function `resizeAvatar` — e só depois de o
  /// ficheiro existir. É esse o sinal de que a foto está pronta: a
  /// escrita antes disso dava um avatar partido no intervalo entre o
  /// envio e a redução.
  final String? photoPath;

  /// O URL pronto a mostrar, escrito pela mesma função.
  ///
  /// Existe para o cliente não ter de chamar `getDownloadURL()` — que é
  /// um pedido de rede por pessoa, e numa lista de cinquenta são
  /// cinquenta. O [photoPath] continua ao lado porque é o que identifica
  /// o ficheiro a apagar; este é o que se mostra.
  final String? photoUrl;

  /// Quando a foto mudou.
  ///
  /// Já não serve para furar a cache — disso trata o token novo dentro
  /// do [photoUrl], que muda o URL a cada envio. Fica porque é a
  /// resposta a "desde quando é esta a foto", que a ficha do aluno
  /// mostra.
  final int? photoUpdatedAt;

  final String uid;
  final String memberNumber;
  final String name;
  final bool active;

  /// Fase 9 (UC27 fechado) — cópia denormalizada do `PaymentRecord` do
  /// MÊS que `currentPaymentPeriod` identifica (`PaymentRepository`
  /// escreve os dois no mesmo `WriteBatch`, mesmo padrão já usado para
  /// `TrainingPlanEntry.currentLoad`/`loadHistory` na Fase 8). Existe
  /// para duas leituras que precisam de ser baratas e não podem esperar
  /// por uma query à subcoleção `paymentRecords`: a lista "Mensalidades
  /// — mês atual" (um pill por membro, sem N+1 queries) e o bloqueio de
  /// login (UC01) — esse último em particular corre em TODA sessão
  /// aberta por um Aluno, não pode custar uma query extra.
  ///
  /// `currentPaymentPeriod` é indispensável a par do estado: sem saber
  /// A QUE MÊS o estado se refere, um registo de Julho ainda `overdue`
  /// continuaria a bloquear o login em Setembro só porque ninguém
  /// tocou no registo desde então. [isOverdueFor] faz essa comparação.
  final PaymentStatus? currentPaymentStatus;
  final String? currentPaymentPeriod;

  /// UC02 — contacto real do membro, editável por ele próprio
  /// (`MyProfileScreen`) ou pelo Gestor (`MemberDetailScreen`).
  /// Distinto do email SINTÉTICO usado só para login
  /// (`login_identifier.dart`) — esse nunca é mostrado nem editável
  /// aqui. `''` quando ainda não preenchido.
  final String phone;
  final String email;

  /// Pedido pelo Carlo depois de testar "Criar utilizador": dados
  /// pessoais adicionais, todos opcionais (`''`/`null` até serem
  /// preenchidos), editáveis só pelo Gestor por agora (`MemberDetailScreen`
  /// — `MyProfileScreen`, self-service, continua limitado a
  /// `phone`/`email`).
  final DateTime? birthDate;
  final String address;
  final String nif;

  /// Texto livre (ex.: "Mãe — 912345678") — não vale a pena modelar
  /// como nome+telefone separados para um único campo de apoio.
  final String emergencyContact;

  /// RGPD (Fase 11). Vazio nas contas criadas antes de isto existir —
  /// essas são levadas ao ecrã de consentimento no primeiro arranque
  /// seguinte, não tratadas como tendo recusado.
  final MemberConsent consent;

  /// UC01 (fechado) — "só uma marcação EXPLÍCITA de atraso bloqueia".
  /// Ausência de registo para o mês [now] (Gestor ainda não marcou
  /// nada, ou o registo é de um mês anterior — `currentPaymentPeriod`
  /// não bate com o mês de [now]) nunca bloqueia; só
  /// `PaymentStatus.overdue` no período CERTO bloqueia. `paidLate`
  /// nunca bloqueia — a mensalidade acabou por ser paga.
  /// `null` quando não há registo para o mês de [now] — nunca marcado,
  /// ou o último registo é de um mês anterior. Centraliza a comparação
  /// de período usada por `ManagePaymentsScreen`, `MyProfileScreen` e
  /// [isOverdueFor], para as três nunca poderem divergir sobre o que
  /// conta como "mês atual".
  PaymentStatus? currentMonthStatus(DateTime now) =>
      currentPaymentPeriod == paymentPeriodKey(now)
          ? currentPaymentStatus
          : null;

  bool isOverdueFor(DateTime now) =>
      currentMonthStatus(now) == PaymentStatus.overdue;

  @override
  List<Object?> get props => [
        uid,
        memberNumber,
        name,
        active,
        phone,
        email,
        birthDate,
        address,
        nif,
        emergencyContact,
        currentPaymentStatus,
        currentPaymentPeriod,
        photoPath,
        photoUrl,
        photoUpdatedAt,
      ];
}
