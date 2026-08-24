import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Traduz os erros do Firebase que um utilizador tem hipótese de
/// encontrar, para uma frase que diz o que aconteceu e o que fazer.
///
/// O que estava antes: o `ErrorState` mostrava sempre a mesma frase
/// genérica ("Não foi possível carregar esta informação") e escondia o
/// código atrás de "Detalhe técnico". Melhor do que despejar a exceção,
/// mas ainda deixa a pessoa sem saber se o problema é dela, da rede, ou
/// da app — e a resposta muda conforme o caso: sem rede espera-se,
/// sem permissões pede-se ao estúdio, e um limite atingido é só esperar
/// um minuto.
///
/// Só traduz o que é acionável. Um `internal` ou um erro desconhecido
/// continuam a cair na frase genérica de propósito: inventar uma
/// explicação para um erro que não percebemos seria pior do que admitir
/// que não sabemos.
String? describeFirebaseError(Object error) {
  final code = _codeOf(error);
  if (code == null) return null;

  return switch (code) {
    // Sem rede, ou o servidor não respondeu a tempo. O mais frequente
    // de longe — num ginásio a ligação cai a toda a hora.
    'unavailable' ||
    'deadline-exceeded' ||
    'network-request-failed' =>
      'Sem ligação ao servidor. Verifica a Internet e tenta outra vez.',

    // O rate limiter (`lib/rateLimit.ts`) devolve exatamente isto.
    'resource-exhausted' =>
      'Demasiados pedidos em pouco tempo. Espera um momento e tenta '
          'outra vez.',
    'permission-denied' =>
      'Não tens permissão para ver ou fazer isto. Se achas que devias '
          'ter, fala com o estúdio.',
    'unauthenticated' => 'A tua sessão expirou. Entra outra vez.',
    'not-found' => 'Isto já não existe — pode ter sido apagado entretanto.',

    // O servidor recusou os dados enviados, e sabe porquê: um campo em
    // falta, um email já usado, uma data malformada. Desde que as
    // Cloud Functions passaram a escrever essas mensagens em português
    // (`lib/validation.ts`), repeti-las é melhor do que inventar uma
    // frase genérica por cima — são elas que dizem QUAL o campo.
    //
    // `_isReadable` existe porque nem toda a mensagem serve: a
    // biblioteca de validação, quando não é traduzida, devolve um bloco
    // de JSON. Nesse caso é preferível a frase genérica.
    'invalid-argument' ||
    'already-exists' ||
    'failed-precondition' when _isReadable(_messageOf(error)) =>
      _messageOf(error)!,
    'invalid-argument' =>
      'Faltam dados ou algum campo está mal preenchido. Confirma o '
          'formulário e tenta outra vez.',
    'already-exists' => 'Isto já existe. Confirma antes de repetir.',

    // App Check a recusar o dispositivo. Raro, mas se acontecer é
    // absolutamente opaco sem uma tradução.
    'failed-precondition' when '$error'.contains('App Check') =>
      'A app não conseguiu confirmar-se junto do servidor. Se estás numa '
          'versão antiga, atualiza.',
    _ => null,
  };
}

/// A mensagem que o servidor mandou, quando a mandou.
String? _messageOf(Object error) {
  if (error is FirebaseFunctionsException) return error.message;
  if (error is FirebaseException) return error.message;
  return null;
}

/// Uma mensagem serve para mostrar se foi escrita para uma pessoa.
///
/// O que se exclui aqui é o despejo técnico: o JSON de um erro de
/// validação, um stack trace, o nome de uma exceção. É melhor uma
/// frase genérica nossa do que um bloco que ninguém lê.
bool _isReadable(String? message) {
  if (message == null) return false;
  final trimmed = message.trim();
  if (trimmed.isEmpty || trimmed.length > 300) return false;
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) return false;
  if (trimmed.toUpperCase() == trimmed && trimmed.length < 40) {
    // "INTERNAL", "UNAVAILABLE" e companhia.
    return false;
  }
  return true;
}

/// O `code` de cada família de exceções do Firebase. São classes
/// diferentes sem interface comum, apesar de todas terem `code`.
String? _codeOf(Object error) {
  if (error is FirebaseFunctionsException) return error.code;
  if (error is FirebaseException) return error.code;
  return null;
}

/// A frase a mostrar ao utilizador para QUALQUER erro.
///
/// Antes disto, quase todos os ecrãs faziam `Text('Não foi possível X:
/// $e')` — e o `$e` de um erro do Firebase é
/// `[firebase_functions/internal] INTERNAL`, ou um bloco de JSON de
/// validação. Ou seja: a app pedia desculpa e a seguir mostrava uma
/// coisa que ninguém consegue ler, muito menos resolver.
///
/// A ordem é deliberada:
///  1. o que o Firebase diz, traduzido ([describeFirebaseError]) — é
///     onde estão os casos acionáveis (sem rede, sem permissão, campo
///     em falta, email repetido);
///  2. a própria mensagem do erro, quando foi escrita para uma pessoa —
///     é o caso das exceções de domínio desta app
///     (`NotEligibleForServiceException` e companhia), que existem
///     precisamente para dizer o que aconteceu em português;
///  3. o [fallback] de quem chamou, que descreve a AÇÃO que falhou.
///
/// O detalhe técnico não desaparece: `ErrorState` continua a mostrá-lo
/// atrás de "Detalhe técnico", e `reportHandledError` continua a
/// enviá-lo para o Crashlytics. O que muda é o que a pessoa lê primeiro.
String userFacingError(Object error, {required String fallback}) {
  final firebase = describeFirebaseError(error);
  if (firebase != null) return firebase;

  final text = error.toString();
  // `Exception: ...` e `_TypeError: ...` são mensagens de programador.
  final looksInternal = text.startsWith('Exception') ||
      text.startsWith('Error') ||
      text.contains('#0') ||
      text.contains('Instance of');
  if (!looksInternal && _isReadable(text)) return text;

  return fallback;
}
