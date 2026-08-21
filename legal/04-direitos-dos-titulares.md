# Procedimento — pedidos dos titulares

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

Artigos 15.º a 22.º do RGPD. Documento interno: é isto que o Gestor faz
quando um aluno pede alguma coisa sobre os seus dados.

---

## Regras que valem para todos os pedidos

**Prazo: um mês** a contar da receção. Prorrogável por mais dois meses
em casos complexos, mas nesse caso é preciso **informar o titular dentro
do primeiro mês**, com a justificação.

**Gratuito.** Só é possível cobrar (ou recusar) perante pedidos
manifestamente infundados ou excessivos, sobretudo pela repetição — e o
ónus de o demonstrar é do estúdio.

**Confirmar a identidade antes de agir.** Se houver dúvida razoável
sobre quem faz o pedido, pode pedir-se informação adicional (artigo
12.º, n.º 6). Para pedidos presenciais de um aluno conhecido, o
reconhecimento pessoal basta e deve ficar anotado.

**Registar tudo.** Quem pediu, quando, o quê, o que foi feito, quando.
Sem este registo não há como demonstrar cumprimento — e o ónus é do
estúdio (artigo 5.º, n.º 2).

> **[ADVOGADO]** Definir o suporte deste registo. A aplicação **não tem**
> um registo de pedidos; se for exigível, é desenvolvimento adicional.
> Uma folha de cálculo com acesso restrito serve à partida.

---

## 1. Acesso e portabilidade (artigos 15.º e 20.º)

*"Quero saber o que têm sobre mim" / "Quero levar os meus dados"*

**Se o titular consegue entrar na aplicação**, o caminho mais rápido é
ele próprio: **Perfil → Os meus dados → Exportar os meus dados**. Dá uma
cópia integral, legível e copiável, em segundos.

**Se não consegue entrar** (conta desativada, esqueceu-se da
palavra-passe, prefere pedir ao balcão), o Gestor exporta por ele:

1. Gestão → Membros → escolher a pessoa
2. A exportação está disponível para qualquer membro do estúdio
3. Entregar o ficheiro por um canal seguro — **não por email não cifrado
   se incluir dados de saúde**

**O que a exportação inclui:** perfil completo, histórico de
consentimentos, avaliações físicas, histórico de cargas, plano de
treino, mensalidades, subscrições, marcações, presenças e utilização
semanal.

**O que não inclui, e porquê:** os identificadores técnicos de
dispositivo, que não têm valor para o titular e são sensíveis se
copiados. A palavra-passe nunca é conhecida por nós — só existe o
resumo criptográfico.

## 2. Retificação (artigo 16.º)

*"Os meus dados estão errados"*

- **Telefone e email**: o próprio corrige na aplicação, sem intermediário.
- **Nome, data de nascimento, morada, NIF, contacto de emergência**:
  Gestão → Membros → escolher a pessoa → editar.
- **Dados de uma avaliação física**: o instrutor edita a avaliação. As
  edições ficam marcadas, e o histórico não é reescrito.

## 3. Apagamento (artigo 17.º)

*"Quero que apaguem tudo"*

**Verificar a identidade presencialmente.** É por isso que a aplicação
não oferece um botão de "apagar a minha conta" ao próprio: uma sessão
aberta pode ser um telemóvel deixado desbloqueado, e isto não tem volta.

**Antes de apagar, avaliar se alguma exceção do n.º 3 se aplica** —
sobretudo a alínea b): cumprimento de obrigação legal. É o caso dos
documentos de suporte à contabilidade.

**Como se faz:** Gestão → Membros → escolher a pessoa → RGPD → Apagar
dados deste membro. É pedido o número de sócio como confirmação.

**O que acontece:**

| Categoria | Resultado |
|---|---|
| Perfil (nome, contactos, NIF, morada, emergência) | Eliminado |
| Consentimentos e respetivo histórico | Eliminado |
| Avaliações físicas | Eliminadas |
| Histórico de cargas e plano de treino | Eliminado |
| Marcações e presenças | Eliminadas |
| Utilização semanal e subscrições | Eliminadas |
| Conta de acesso | Eliminada — deixa de conseguir autenticar-se |
| **Registos de pagamento** | **Anonimizados, não eliminados** |

**Explicar isto ao titular, e por escrito.** O artigo 17.º, n.º 3,
alínea b) excetua o tratamento necessário ao cumprimento de uma
obrigação legal, e a legislação fiscal impõe a conservação dos
documentos de suporte à contabilidade. Fica o valor e o período; sai
tudo o que liga o registo a uma pessoa identificável.

A aplicação devolve a contagem separada — quantos registos foram
apagados e quantos foram anonimizados — precisamente para que o Gestor
possa dizer ao titular o que ficou.

> **[ADVOGADO]** Confirmar o prazo e a norma (documento 06), e validar
> se a anonimização praticada é suficiente para os dados deixarem de ser
> pessoais. Nota técnica honesta: **o registo continua debaixo de um
> identificador interno do antigo membro**. Sem os dados de perfil (que
> são eliminados) esse identificador não é reversível a uma pessoa, mas
> a avaliação é jurídica, não minha.

## 4. Retirada do consentimento (artigo 7.º, n.º 3)

*"Já não quero que me façam avaliações"*

O próprio faz, sozinho: **Perfil → Os meus dados → Avaliações físicas**,
desligar.

**Efeito imediato:** deixam de poder ser registadas novas avaliações —
recusadas pelo servidor, não apenas escondidas na interface.

**Efeito que NÃO tem:** as avaliações já feitas continuam guardadas.
Isto é dito ao titular no momento em que desliga o interruptor. Se
quiser que desapareçam, é um pedido de apagamento (ponto 3), que é uma
ação distinta e deliberada.

## 5. Limitação do tratamento (artigo 18.º)

*"Não apaguem, mas parem de usar enquanto isto não se resolve"*

**A aplicação não tem uma função dedicada.** Aproximação possível:
desativar o membro (deixa de poder marcar e de receber planos novos) e
retirar o consentimento de saúde (impede novas avaliações).

> **[ADVOGADO]** Avaliar se isto satisfaz o artigo 18.º ou se é preciso
> um mecanismo próprio. Se for, é desenvolvimento adicional — e vale a
> pena saber quão provável é o cenário antes de o construir.

## 6. Oposição (artigo 21.º)

*"Não quero que tratem os meus dados"*

Aplica-se ao tratamento fundado em interesse legítimo — no nosso caso,
apenas segurança e diagnóstico técnico. Não se aplica ao tratamento
necessário à execução do contrato: quem se opõe a esse está, na prática,
a pedir o fim da relação com o estúdio.

Se a oposição for ao tratamento de dados de saúde, é uma retirada de
consentimento (ponto 4).

## 7. Decisões automatizadas (artigo 22.º)

*"Bloquearam-me o acesso"*

Ver documento 01, secção 9: a suspensão por mensalidade em atraso decorre
de uma marcação feita por uma pessoa do estúdio, não de uma decisão
automática. Verificar o registo — cada marcação guarda **quem** a fez e
**quando** — e resolver com o titular.

---

## Modelo de resposta a um pedido de acesso

> [Nome do titular]
>
> Em resposta ao seu pedido de [data], enviamos em anexo a cópia dos
> dados pessoais que tratamos a seu respeito.
>
> O ficheiro inclui: dados de identificação e contacto, histórico de
> consentimentos, marcações e presenças, registos de mensalidades,
> subscrições e — caso tenha autorizado o respetivo tratamento —
> avaliações físicas, plano de treino e histórico de cargas.
>
> As finalidades, os fundamentos, os prazos de conservação e os
> destinatários constam da nossa Política de Privacidade, disponível em
> [endereço].
>
> Recordamos que pode solicitar a retificação ou o apagamento dos seus
> dados, e que tem o direito de apresentar reclamação à Comissão
> Nacional de Proteção de Dados.
>
> [Estúdio] · [data]
