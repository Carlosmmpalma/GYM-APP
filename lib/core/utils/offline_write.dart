import 'dart:async';

/// O que aconteceu a uma escrita direta no Firestore.
enum WriteOutcome {
  /// O servidor confirmou.
  confirmed,

  /// Ficou na fila local do Firestore. Vai sozinha quando a ligação
  /// voltar — não se perdeu nada, só ainda não chegou lá.
  queued,
}

/// Espera pela confirmação do servidor, mas não para sempre.
///
/// Com a cache offline ligada (Fase 8), o `Future` de um `set()` ou
/// `update()` do Firestore **só completa quando o servidor confirma**.
/// A cache local e os listeners atualizam-se logo — mas o `await` fica
/// pendurado. Num ginásio, onde a ligação cai a toda a hora e o
/// instrutor está a marcar presenças com o telemóvel na mão, isso
/// traduz-se num botão que roda para sempre, sem erro e sem sucesso:
/// a pessoa toca outra vez, e outra, convencida de que não funcionou.
///
/// Passado [timeout] assume-se que a escrita ficou em fila e devolve-se
/// o controlo à UI. **A escrita não é cancelada** — o Firestore
/// encarrega-se dela; deixa-se só de a esperar, para poder dizer à
/// pessoa o que realmente se passa.
///
/// Um erro que aconteça **enquanto ainda estamos à espera** sobe
/// normalmente para quem chamou: se as Rules recusam a escrita à
/// frente do utilizador, ele tem de saber. O que se engole é só o erro
/// que chegue DEPOIS de termos desistido — nessa altura já ninguém
/// está à escuta, e deixá-lo solto rebentaria como erro não tratado
/// num sítio sem relação nenhuma com o que se estava a fazer.
Future<WriteOutcome> writeOrQueue(
  Future<void> write, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  // Segundo ouvinte, anexado antes de qualquer espera: existe só para
  // que uma falha tardia tenha sempre quem a apanhe. Não interfere com
  // o `await` abaixo — em Dart, cada ouvinte de um `Future` recebe o
  // resultado (ou o erro) por sua conta.
  unawaited(write.then((_) {}, onError: (Object _, StackTrace __) {}));

  try {
    await write.timeout(timeout);
    return WriteOutcome.confirmed;
  } on TimeoutException {
    return WriteOutcome.queued;
  }
}

/// A frase a mostrar depois de uma escrita, para não anunciar como
/// concluído o que ainda está na fila.
String writeOutcomeMessage(
  WriteOutcome outcome, {
  required String confirmed,
}) {
  return switch (outcome) {
    WriteOutcome.confirmed => confirmed,
    WriteOutcome.queued => 'Guardado no telemóvel. Assim que houver '
        'ligação, sobe sozinho — não precisas de repetir.',
  };
}
