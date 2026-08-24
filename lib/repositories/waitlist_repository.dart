import '../domain/entities/waitlist_entry.dart';

/// Fase 11 — lista de espera de sessões cheias.
///
/// Entrar e sair são Cloud Functions pela mesma razão que marcar:
/// decidir exige ler a ocorrência e as subscrições do membro, e essa
/// decisão não pode ficar do lado do cliente. As Security Rules
/// bloqueiam escrita direta na coleção (`allow write: if false`).
abstract class WaitlistRepository {
  /// Lança [WaitlistHasCapacityException] (a sessão afinal tem vagas —
  /// devia marcar, não esperar), [WaitlistAlreadyBookedException] ou
  /// [WaitlistNotEligibleException]. Entrar duas vezes não é erro: a
  /// segunda chamada não faz nada e não avança na fila.
  Future<void> join({required String occurrenceId, required String memberId});

  Future<void> leave({required String occurrenceId, required String memberId});

  /// A própria entrada, ou `null` se não estiver na fila. Só a do
  /// próprio (ou de qualquer membro, se for staff) — as Rules não
  /// deixam ninguém listar a fila inteira.
  Stream<WaitlistEntry?> watchEntry({
    required String occurrenceId,
    required String memberId,
  });

  /// A fila inteira, por ordem de chegada. Só Instrutor/Gestor — as
  /// Rules recusam a listagem a um aluno, e é essa a razão de a
  /// posição ser escrita pelo servidor em cada entrada.
  Stream<List<WaitlistEntry>> watchQueue(String occurrenceId);
}

class WaitlistHasCapacityException implements Exception {
  const WaitlistHasCapacityException();
  @override
  String toString() => 'Esta sessão tem vagas — podes marcar já.';
}

class WaitlistAlreadyBookedException implements Exception {
  const WaitlistAlreadyBookedException();
  @override
  String toString() => 'Já tens esta sessão marcada.';
}

class WaitlistNotEligibleException implements Exception {
  const WaitlistNotEligibleException();
  @override
  String toString() => 'O teu plano não inclui este serviço.';
}
