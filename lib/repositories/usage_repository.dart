import '../domain/entities/usage.dart';

/// Fase 4 — leitura do read model de utilização (`usage/{memberId}_
/// {serviceId}_{period}`). Só leitura: quem escreve é sempre
/// `createBooking`/`cancelBooking`/`recalculateUsage` (Cloud Functions,
/// Admin SDK) — ver `firestore.rules` (`allow write: if false`).
abstract class UsageRepository {
  /// `null` quando ainda não existe nenhum documento para este
  /// membro+serviço+período — equivalente a `used == 0` (a Cloud
  /// Function só cria o documento na primeira marcação que consome
  /// utilização desse período).
  Stream<Usage?> watchUsage({
    required String memberId,
    required String serviceId,
    required String period,
  });

  /// Fase 4 story 6 — ferramenta de operação do Gestor: reconstrói
  /// `usage/{memberId}_{serviceId}_{period}` a partir dos `Booking`s
  /// reais (Cloud Function `recalculateUsage`, ver
  /// `firebase/functions/src/recalculateUsage.ts`). Devolve um período
  /// por cada entrada recalculada (inclui períodos que ficaram a 0 —
  /// ver nota na própria Cloud Function), ordem indefinida.
  Future<List<UsageRecalculationEntry>> recalculateUsage({
    required String memberId,
    required String serviceId,
  });
}

/// `period` no formato ISO week (`isoWeekKey`) + `used` recalculado a
/// partir dos bookings reais nesse período, tal como devolvido por
/// `recalculateUsage`. Não é um [Usage] completo de propósito — não
/// vem com `limit` (nunca esteve nele, ver `usage.dart`) nem é algo
/// que se subscreva; é só o resultado de uma ação pontual.
typedef UsageRecalculationEntry = ({String period, int used});
