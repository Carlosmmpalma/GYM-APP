// Arranque próprio, em vez do que o Flutter gera por omissão.
//
// Existe por uma razão só: **tirar o ecrã de arranque** (ver
// `web/index.html`). O ficheiro gerado limita-se a chamar
// `_flutter.loader.load(...)` e não dá gancho nenhum para saber quando a
// app já está viva — sem isto, ou não havia ecrã de arranque, ou ficava
// lá para sempre por cima da app.
//
// As linhas com chavetas duplas abaixo são marcas que o `flutter build
// web` substitui: o carregador do motor, a lista de builds disponíveis
// (wasm e JS, para o browser escolher) e a versão da cache offline. Não
// se editam à mão — e não se escrevem em comentários, porque a
// substituição também acontece lá dentro: injeta o carregador inteiro a
// meio de um `//`, e o ficheiro deixa de ser JavaScript válido.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    // `runApp()` resolve quando a app arranca, não quando o primeiro
    // fotograma está pintado — faltam um ou dois. Daí o desvanecer em vez
    // de um corte seco: cobre essa fresta sem ninguém dar por ela, e se
    // for mais longa do que o previsto vê-se o ecrã de arranque a sair, e
    // não um piscar preto.
    //
    // Sem `requestAnimationFrame`: num separador em segundo plano ele NÃO
    // dispara, e o ecrã de arranque ficava preso por cima de uma app já a
    // funcionar até alguém voltar ao separador. Apanhei isto a testar com
    // o painel do browser escondido.
    //
    // Quem faz a remoção é o `index.html` — lá está também o prazo de
    // segurança para o caso de isto nunca chegar a ser chamado.
    if (typeof window.__removerSplash === 'function') {
      window.__removerSplash();
    }
  },
});
