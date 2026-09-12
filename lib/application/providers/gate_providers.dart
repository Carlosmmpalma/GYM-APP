import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payment_providers.dart';
import 'privacy_providers.dart';
import 'tenant_context_providers.dart';

/// Que ecrã o [AuthGate] deve mostrar.
///
/// A ordem das constantes é a ordem de precedência: quem tem password
/// temporária vai lá ter antes de tudo, e o bloqueio por mensalidade é o
/// último a decidir.
enum GateScreen { login, forcePasswordChange, consent, blocked, home }

/// O resultado de uma verificação — ou o erro dela, sem rebentar.
///
/// Serve para as três correrem juntas sem que uma leve as outras
/// atrás: uma falha a ler a mensalidade não pode impedir alguém de
/// chegar ao ecrã de trocar a password. Quem decide o que fazer com
/// cada erro é o [gateScreenProvider], caso a caso.
typedef _Verificacao<T> = ({T? valor, Object? erro});

Future<_Verificacao<T>> _semRebentar<T>(Future<T> futuro) async {
  try {
    return (valor: await futuro, erro: null);
  } catch (erro) {
    return (valor: null, erro: erro);
  }
}

/// Resolve as três verificações do arranque **ao mesmo tempo**.
///
/// O `AuthGate` encadeava-as: cada uma só começava quando a anterior
/// acabasse, e cada uma tinha o seu ecrã de espera. Eram três idas ao
/// servidor em fila, sempre, entre autenticar e ver a app — logo a
/// seguir a o utilizador já ter esperado pela app inteira a descarregar.
///
/// Nenhuma delas usa o resultado da outra: todas dependem só do
/// [AppUser]. Estavam em série apenas porque foram escritas encaixadas
/// umas nas outras. Assim espera-se pela mais lenta em vez da soma, e
/// vê-se um ecrã de espera em vez de três.
///
/// O preço é fazer trabalho que às vezes se deita fora: quem tem
/// password temporária não precisava das outras duas respostas. É uma
/// leitura extra num caso raro, para poupar duas viagens de rede no caso
/// normal.
///
/// **Cada erro é tratado onde importa, e não em conjunto.** Encadeadas,
/// as verificações que vinham depois nunca chegavam a correr quando uma
/// anterior decidia o ecrã; em paralelo correm sempre, e um erro numa
/// delas ia bloquear um caminho a que não pertence — uma falha a ler a
/// mensalidade deixava alguém com password temporária preso num ecrã de
/// erro, sem forma de a trocar. Por isso:
///
/// - **password temporária**: o erro sobe. Sem esta resposta não se
///   decide nada, e deixar entrar quem devia trocar a password seria
///   saltar o UC22.
/// - **consentimento**: o erro vale por "não é preciso pedir", que é o
///   que já acontecia antes (o ecrã lia `valueOrNull == true`, e um erro
///   dava `null`). Ver também `needsConsentProvider`, que já engole os
///   seus próprios erros pela mesma razão.
/// - **mensalidade**: o erro sobe, mas só se a decisão chegar aqui.
///
/// A precedência entre os ecrãs é a mesma de antes, e as razões também:
/// o consentimento vem DEPOIS da password temporária (não se pede a
/// alguém que ainda não controla a própria conta) e ANTES do bloqueio
/// por mensalidade (quem está em atraso continua a ter direito a decidir
/// sobre os seus dados).
final gateScreenProvider = FutureProvider.autoDispose<GateScreen>((ref) async {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null) return GateScreen.login;

  // As três arrancam aqui, juntas. O `await` só vem a seguir.
  final (temporaria, consentimento, mensalidade) = await (
    _semRebentar(ref.watch(hasTemporaryPasswordProvider.future)),
    _semRebentar(ref.watch(needsConsentProvider.future)),
    _semRebentar(ref.watch(isBlockedForOverduePaymentProvider.future)),
  ).wait;

  if (temporaria.erro != null) throw temporaria.erro!;
  if (temporaria.valor == true) return GateScreen.forcePasswordChange;

  if (consentimento.valor == true) return GateScreen.consent;

  if (mensalidade.erro != null) throw mensalidade.erro!;
  return mensalidade.valor == true ? GateScreen.blocked : GateScreen.home;
});
