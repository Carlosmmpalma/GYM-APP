# Dossier de proteção de dados — para revisão jurídica

**Estes documentos são um rascunho técnico, não aconselhamento
jurídico.** Foram redigidos por quem escreveu a aplicação, a partir do
que o código **de facto** faz — campo a campo, tabela a tabela. O valor
que têm é esse: descrevem o tratamento real, não uma versão idealizada.
O que lhes falta é a validação de quem responde por ela.

Todos os pontos marcados **[ADVOGADO]** são decisões jurídicas que não
me competem. Os marcados **[PREENCHER]** são dados da empresa que eu não
tenho.

## Porque é que isto é preciso

A aplicação trata **dados de saúde**: pressão arterial, percentagem de
massa gorda, gordura visceral, metabolismo basal, perímetros corporais.
O artigo 9.º do RGPD coloca-os numa categoria especial, cujo tratamento
é proibido salvo exceção — no nosso caso, consentimento explícito do
titular.

Isto muda o patamar: deixa de ser "convém ter uma política de
privacidade" e passa a ser um conjunto de obrigações com prazos e
coimas próprias.

## Os documentos

| # | Documento | Para quê | Quem vê |
|---|---|---|---|
| 01 | [Política de Privacidade](01-politica-de-privacidade.md) | Cumprir o dever de informar (artigos 13.º e 14.º) | Público — site, app, ficha de inscrição |
| 02 | [Registo de Atividades de Tratamento](02-registo-de-tratamentos.md) | Obrigatório com dados do artigo 9.º (artigo 30.º) | Interno; entregue à CNPD se pedido |
| 03 | [Consentimento para dados de saúde](03-consentimento-dados-de-saude.md) | Base legal do artigo 9.º, n.º 2, alínea a) | Titular, no ecrã e em papel |
| 04 | [Direitos dos titulares](04-direitos-dos-titulares.md) | Procedimento de resposta (artigos 15.º a 22.º) | Interno |
| 05 | [Violação de dados](05-violacao-de-dados.md) | Notificação em 72 horas (artigos 33.º e 34.º) | Interno |
| 06 | [Conservação e eliminação](06-conservacao-e-eliminacao.md) | Prazos por categoria de dados | Interno |
| 07 | [Necessidade de AIPD e de EPD](07-necessidade-de-aipd.md) | Avaliar se são obrigatórios (artigos 35.º e 37.º) | Interno |
| 08 | [Subcontratantes](08-subcontratantes.md) | Contratos e transferências (artigos 28.º e 44.º e ss.) | Interno |
| 09 | [Declarações nas lojas](09-lojas-de-aplicacoes.md) | Formulários da Apple e da Google | Submissão |

## O que o código já faz, e que o advogado pode dar como assente

Não são intenções — está implementado e testado contra o servidor:

- **Consentimento explícito e separado** para dados de saúde, opcional,
  recolhido antes do primeiro uso e registado com data do servidor e
  versão do texto. Há um histórico imutável de cada alteração.
- **A recusa não impede usar o serviço.** Sem consentimento, o aluno
  marca aulas e treino livre na mesma; só não podem ser feitas
  avaliações físicas. Isto é aplicado pelo **servidor**, não escondido
  na interface: um instrutor autenticado, a escrever diretamente à base
  de dados, é recusado. Há um teste automático que o prova.
- **Retirar o consentimento é tão fácil como dá-lo**: o mesmo
  interruptor, no perfil do próprio.
- **Exportação de todos os dados** de um titular, self-service.
- **Eliminação** com anonimização dos registos financeiros que a lei
  fiscal obriga a conservar.
- **Isolamento entre ginásios** verificado por testes automáticos.
- **Privacidade entre alunos do mesmo ginásio**: cada aluno só lê o seu
  próprio perfil e as suas próprias marcações. Numa aula vê a contagem
  de lugares, nunca os nomes.
- **Medidas de segurança** do artigo 32.º descritas no documento 02.

## O que falta decidir, e é do advogado

1. Se é preciso **Encarregado de Proteção de Dados** (documento 07).
2. Se é preciso **Avaliação de Impacto** (documento 07).
3. Os **prazos de conservação** propostos no documento 06 — propus-os
   por analogia e bom senso, não por norma.
4. Como tratar o **contacto de emergência**: é um terceiro cujos dados
   são recolhidos sem ele estar presente (documento 01, secção 4).
5. Se vão aceitar **menores de idade** e como recolher o consentimento
   dos representantes legais.
6. Confirmar o prazo de retenção fiscal e a norma aplicável
   (documento 06).
7. Rever a análise sobre **decisões automatizadas** (documento 01,
   secção 9) — a app bloqueia o acesso por mensalidade em atraso.

## Depois da revisão

Se o texto da política mudar de forma relevante, é preciso subir
`kPrivacyPolicyVersion` em `lib/domain/entities/consent.dart`. Isso faz
a app voltar a pedir aceitação a toda a gente no arranque seguinte, e é
o mecanismo previsto para quando o tratamento muda. Não subir por
correções de gralhas: pedir consentimento outra vez sem motivo treina as
pessoas a aceitar sem ler.

O texto que a app mostra vive em
`lib/presentation/screens/consent_screen.dart` e tem de ficar coerente
com o documento 01.
