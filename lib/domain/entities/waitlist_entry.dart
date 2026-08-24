import 'package:equatable/equatable.dart';

/// Fase 11 — o lugar de alguém na fila de uma sessão cheia.
///
/// Vive em `sessionOccurrences/{id}/waitlist/{memberId}`: o id do
/// documento é o `memberId`, o que torna impossível entrar duas vezes
/// na mesma fila sem ter de verificar nada.
///
/// [position] é escrita pelo servidor e recalculada a cada entrada,
/// saída e promoção — não é derivada no cliente porque um aluno não
/// pode listar a fila (quem mais está à espera é informação dos
/// outros). Ver `firebase/functions/src/lib/waitlist.ts`.
class WaitlistEntry extends Equatable {
  const WaitlistEntry({
    required this.memberId,
    required this.joinedAt,
    required this.position,
  });

  final String memberId;
  final DateTime joinedAt;

  /// 1 = próximo a entrar. `null` no instante entre a entrada na fila e
  /// a numeração chegar — a app mostra "na lista de espera" sem número
  /// nesse caso, em vez de mostrar um número errado.
  final int? position;

  @override
  List<Object?> get props => [memberId, joinedAt, position];
}
