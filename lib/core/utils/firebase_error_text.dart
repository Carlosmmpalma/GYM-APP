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

    // App Check a recusar o dispositivo. Raro, mas se acontecer é
    // absolutamente opaco sem uma tradução.
    'failed-precondition' when '$error'.contains('App Check') =>
      'A app não conseguiu confirmar-se junto do servidor. Se estás numa '
          'versão antiga, atualiza.',
    _ => null,
  };
}

/// O `code` de cada família de exceções do Firebase. São classes
/// diferentes sem interface comum, apesar de todas terem `code`.
String? _codeOf(Object error) {
  if (error is FirebaseFunctionsException) return error.code;
  if (error is FirebaseException) return error.code;
  return null;
}
