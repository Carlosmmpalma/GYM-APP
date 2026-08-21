# Consentimento para tratamento de dados de saúde

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

Artigo 9.º, n.º 2, alínea a) do RGPD.

---

## Porque é que este documento existe à parte

Aceitar a política de privacidade e autorizar o tratamento de dados de
saúde **não são a mesma coisa**, e juntá-los seria um erro com
consequências:

- A política de privacidade é o cumprimento do **dever de informar**. O
  tratamento corrente (marcações, mensalidades) tem por base a execução
  do contrato, não o consentimento — e um consentimento pedido onde não
  é preciso confunde o titular sobre o que pode realmente recusar.
- Os dados de saúde **exigem consentimento explícito e específico**.

E o artigo 7.º, n.º 4 acrescenta a condição que determina o desenho: o
consentimento não é livre se for condição de acesso a um serviço que
dele não depende. Marcar aulas não depende de autorizar avaliações
físicas.

**Daí a regra que a aplicação implementa: o interruptor começa
desligado, "Continuar" funciona com ele desligado, e quem recusa usa a
aplicação inteira menos as avaliações.**

## Os quatro requisitos, e como são cumpridos

| Requisito (artigo 4.º, n.º 11 e artigo 7.º) | Como |
|---|---|
| **Livre** | Opcional. Recusar não impede usar o serviço, e a app fá-lo por inteiro sem ele |
| **Específico** | Um consentimento só para dados de saúde, separado da aceitação da política |
| **Informado** | O ecrã descreve o que é recolhido, para quê, quem vê, e o que acontece se recusar |
| **Inequívoco** | Ato positivo: um interruptor desligado por omissão, que o titular tem de ligar |
| **Demonstrável** (art. 7.º/1) | Registo no servidor com data do servidor, versão do texto e histórico imutável |
| **Retirável** (art. 7.º/3) | Mesmo interruptor, no perfil do próprio, sem justificação |

Sobre a demonstrabilidade, um detalhe que interessa a uma inspeção: o
registo **não é escrito pela aplicação no dispositivo**. É criado por
uma função no servidor, com data do servidor. Um campo escrito pelo
cliente, com data escolhida pelo cliente, não demonstra nada — reescreve-
se à vontade. As regras de acesso impedem o cliente de tocar no campo.

Além do estado atual, é mantido um registo **append-only** de cada
alteração. A prova que interessa é "consentiu em X, retirou em Y", não o
valor de hoje.

---

## Texto apresentado na aplicação

Este é o texto que o ecrã mostra hoje. Vive em
`lib/presentation/screens/consent_screen.dart` e tem de ficar coerente
com a política de privacidade revista.

> ### OS TEUS DADOS
>
> Antes de continuares, precisas de saber o que o estúdio guarda sobre
> ti e para quê.
>
> **Quem trata os teus dados** — O estúdio onde estás inscrito. É ele
> quem decide o que é recolhido e para quê.
>
> **O que é guardado** — Nome, número de sócio, contactos, data de
> nascimento, NIF, morada e contacto de emergência. As tuas marcações e
> presenças. As mensalidades. E, se autorizares, as avaliações físicas e
> o histórico de cargas do teu plano de treino.
>
> **Para quê** — Gerir a tua inscrição, deixar-te marcar treinos,
> controlar o limite semanal do teu plano e acompanhar a tua evolução.
>
> **Quem vê** — O Gestor do estúdio e os instrutores. Mais ninguém —
> nenhum outro aluno vê os teus dados, e nada é partilhado com terceiros
> para publicidade.
>
> **Os teus direitos** — Podes pedir uma cópia de tudo o que temos sobre
> ti, corrigir o que estiver errado, ou pedir que seja apagado. A
> exportação está no teu perfil; o apagamento pede-se ao estúdio, que
> confirma a tua identidade antes de o fazer.
>
> **O que fica mesmo depois de apagar** — Os registos de pagamento, sem
> o teu nome associado: a lei obriga o estúdio a guardar a contabilidade
> durante 10 anos.
>
> ---
>
> **[ ] Autorizo avaliações físicas**
> Peso, massa gorda, pressão arterial e outras medidas que o instrutor
> registe.
>
> *É opcional. Sem isto continuas a marcar aulas e treino livre
> normalmente — só não podem ser feitas avaliações. Podes mudar de
> ideias a qualquer momento no teu perfil.*
>
> **[ Continuar ]**
>
> Ao continuar confirmas que leste esta informação.

> **[ADVOGADO]** Rever sobretudo:
> 1. Se "Ao continuar confirmas que leste esta informação" é a fórmula
>    adequada — não é um consentimento, é o cumprimento do dever de
>    informar, e a redação deve deixá-lo claro.
> 2. Se o resumo é suficiente ou se deve remeter para a política
>    integral com uma ligação (hoje não há ligação; se for preciso, é
>    trabalho de desenvolvimento).
> 3. A menção aos 10 anos — confirmar o prazo e a norma (documento 06).

---

## Texto para a ficha de inscrição em papel

Para quem se inscreve ao balcão, antes de ter acesso à aplicação.

> **Autorização para tratamento de dados de saúde**
>
> Eu, ____________________________________, portador(a) do NIF
> ____________, declaro que fui informado(a) de que o
> [PREENCHER: nome do estúdio] pretende recolher e tratar dados
> relativos à minha saúde — nomeadamente peso, altura, composição
> corporal, pressão arterial, perímetros corporais e níveis de
> aptidão física — com a finalidade de avaliar a minha condição física,
> elaborar e ajustar o meu plano de treino e acompanhar a minha
> evolução.
>
> Fui informado(a) de que:
>
> - esta autorização é **livre e facultativa**, e que a sua recusa **não
>   me impede** de me inscrever nem de utilizar os serviços do estúdio,
>   incluindo a marcação de aulas e de treino livre;
> - posso **retirá-la a qualquer momento**, sem justificação, através da
>   aplicação ou por comunicação ao estúdio, sem que isso afete a
>   licitude do tratamento já efetuado;
> - a retirada da autorização impede novas avaliações, mas **não elimina
>   automaticamente** as já realizadas, cuja eliminação posso pedir em
>   separado;
> - os meus dados são acessíveis apenas ao Gestor e aos instrutores do
>   estúdio.
>
> Tomei conhecimento da Política de Privacidade, disponível em
> [PREENCHER: endereço] e na aplicação.
>
> ( ) **Autorizo** o tratamento dos meus dados de saúde
> ( ) **Não autorizo**
>
> Data: ____/____/________
>
> Assinatura: ______________________________________
>
> ---
> *Uso interno — registado na aplicação em ____/____/____ por __________*

> **[ADVOGADO]** As duas caixas explícitas (autorizo / não autorizo)
> evitam a ambiguidade de uma caixa deixada em branco. Confirmar se é a
> forma preferida, e se a declaração deve ser assinada em documento
> autónomo em vez de integrada no contrato de inscrição — o artigo 7.º,
> n.º 2 exige que, num documento que trate de outros assuntos, o pedido
> de consentimento seja apresentado de forma **claramente distinta**.

---

## Coerência entre o papel e a aplicação

Se alguém assinar a autorização em papel, isso **não fica registado na
aplicação automaticamente**. A app volta a perguntar no primeiro acesso.

Não é um defeito: o registo digital é o que fica com data do servidor e
versão do texto, e é esse que serve de prova. O papel serve o momento da
inscrição presencial. Convém que o procedimento interno o diga
claramente, para ninguém pensar que uma coisa dispensa a outra.
