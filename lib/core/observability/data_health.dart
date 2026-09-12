import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quantos providers estão neste momento em erro.
///
/// ## O problema que isto resolve
///
/// A app tem 54 sítios (em 22 ficheiros) escritos assim:
///
/// ```dart
/// final membros = ref.watch(membersProvider).valueOrNull ?? const [];
/// ```
///
/// Cada um deles trata **três coisas diferentes como a mesma**: "ainda
/// não carregou", "falhou a carregar" e "está mesmo vazio". Nos dois
/// primeiros casos o ecrã desenha-se como se o estúdio não tivesse nada
/// — e não diz nada a ninguém.
///
/// Isto não é hipotético. Apanhei-o a testar a app a sério: a cache
/// local do Firestore ficou corrompida (`refusing to open IndexedDB
/// database`) e o instrutor viu o seu próprio ecrã inicial com um "?" no
/// lugar do nome, "0 sessões hoje" e "0 alunos ativos". Tudo plausível,
/// tudo falso, e sem um único sinal de que alguma coisa tinha corrido
/// mal. Acontece com quota cheia, navegação privada, limpeza do browser,
/// ou várias abas abertas — a persistência na web é de aba única, como o
/// próprio `bootstrap.dart` já assinala.
///
/// ## Porque um observador e não 54 correções
///
/// Corrigir cada sítio significaria trocar `valueOrNull ?? []` por um
/// `.when(error: ...)` em 54 lugares, cada um a inventar a sua forma de
/// mostrar o erro. Seria muito trabalho para um resultado inconsistente,
/// e o 55.º sítio a ser escrito nasceria outra vez errado.
///
/// O Riverpod já sabe quando um provider falha. Ouvir isso num sítio só
/// dá a resposta certa para todos — incluindo os que ainda não existem.
///
/// ## O que NÃO faz
///
/// Não substitui o tratamento de erro de um ecrã. Um ecrã cujo conteúdo
/// principal falhou deve continuar a dizê-lo no sítio onde a informação
/// devia estar ([ErrorState] existe para isso). Isto é a rede por baixo:
/// garante que um erro nunca passa em silêncio, mesmo onde ninguém se
/// lembrou de o tratar.
class DataHealth extends StateNotifier<Set<String>> {
  DataHealth() : super(const {});

  void registarFalha(String provider) {
    if (state.contains(provider)) return;
    state = {...state, provider};
  }

  void registarRecuperacao(String provider) {
    if (!state.contains(provider)) return;
    state = {...state}..remove(provider);
  }
}

final dataHealthProvider =
    StateNotifierProvider<DataHealth, Set<String>>((ref) => DataHealth());

/// Liga os erros dos providers ao [dataHealthProvider].
///
/// Registado no `ProviderScope` do arranque. Um observador é o único
/// sítio onde se consegue ver TODOS os providers sem os tocar um a um.
class DataHealthObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _registar(provider, newValue, container);
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    _registar(provider, value, container);
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    // Um provider `autoDispose` que morre com um erro em cima não vai
    // voltar a avisar de nada — deixá-lo na lista mantinha o aviso no
    // ecrã para sempre.
    _comContainer(container, (saude) {
      saude.registarRecuperacao(_nome(provider));
    });
  }

  /// Lê o registo de saúde sem nunca rebentar.
  ///
  /// Quando o próprio `ProviderContainer` é destruído, os providers que
  /// vivem dentro dele são destruídos também — e o observador é chamado
  /// para cada um. Nessa altura já não há container de onde ler, e
  /// tentar fazê-lo lançava. Um observador que deita a app abaixo ao
  /// fechar é exatamente o contrário do que isto existe para fazer.
  void _comContainer(
    ProviderContainer container,
    void Function(DataHealth saude) acao,
  ) {
    try {
      acao(container.read(dataHealthProvider.notifier));
    } catch (_) {
      // Observabilidade é sempre o melhor esforço, nunca uma exigência.
    }
  }

  void _registar(
    ProviderBase<Object?> provider,
    Object? valor,
    ProviderContainer container,
  ) {
    if (valor is! AsyncValue) return;
    // O próprio `dataHealthProvider` não se observa a si mesmo.
    if (provider == dataHealthProvider) return;

    final nome = _nome(provider);
    _comContainer(container, (saude) {
      if (valor.hasError) {
        saude.registarFalha(nome);
      } else if (valor.hasValue) {
        // `hasValue` e não `!hasError`: o estado de carregamento não é
        // recuperação — um provider a recarregar depois de falhar passa
        // por `loading` antes de se saber se resolveu.
        saude.registarRecuperacao(nome);
      }
    });
  }

  /// O `argument` entra no nome porque uma família tem um estado por
  /// chave: `memberProfile(a)` pode falhar enquanto `memberProfile(b)`
  /// está bem, e registá-los com o mesmo nome fazia a recuperação de um
  /// apagar a falha do outro.
  String _nome(ProviderBase<Object?> provider) {
    final base = provider.name ?? provider.runtimeType.toString();
    final arg = provider.argument;
    return arg == null ? base : '$base($arg)';
  }
}
