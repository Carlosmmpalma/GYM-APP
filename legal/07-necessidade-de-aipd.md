# Avaliação: é preciso AIPD? É preciso EPD?

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

Artigos 35.º (Avaliação de Impacto sobre a Proteção de Dados) e 37.º
(Encarregado de Proteção de Dados).

**Este é o documento em que menos confio.** As duas perguntas dependem
de interpretar "grande escala" e "atividade principal", e a resposta
para um estúdio único não é evidente. O que faço aqui é apresentar os
argumentos dos dois lados com os factos certos, para o advogado decidir.

---

## Parte A — Avaliação de Impacto (artigo 35.º)

### Quando é obrigatória

O n.º 1 impõe AIPD quando o tratamento for **suscetível de implicar um
risco elevado** para os direitos e liberdades. O n.º 3 dá três casos em
que é sempre necessária, e um deles interessa-nos:

> alínea b) — *"Operações de tratamento em grande escala de categorias
> especiais de dados a que se refere o artigo 9.º"*

Toda a questão está em **"grande escala"**.

### Argumentos a favor de NÃO ser obrigatória

- **Volume.** Um estúdio único trata dados de saúde de algumas centenas
  de pessoas. O considerando 91 exclui expressamente o tratamento por um
  médico individual, o que sugere que a escala relevante é bastante
  superior.
- **Âmbito geográfico.** Um estabelecimento, uma cidade.
- **Duração e permanência.** As avaliações são pontuais — algumas por
  ano por aluno — e não um fluxo contínuo de dados de saúde.
- **Sensibilidade relativa.** São medidas de composição corporal e
  aptidão física, não diagnósticos, patologias ou tratamentos.
- **Consentimento e alternativa real.** O titular pode recusar e
  continuar a usar o serviço por inteiro.

### Argumentos a favor de SER obrigatória

- A alínea b) não fixa números, e as autoridades tendem a ser exigentes
  com o artigo 9.º.
- O tratamento é **sistemático** — parte do modelo de serviço, não uma
  exceção.
- Combina dados de saúde com identificação completa (NIF, morada, data
  de nascimento) e dados financeiros no mesmo sistema.
- **Se o projeto crescer para vários estúdios**, o argumento do volume
  desaparece. A aplicação é multi-tenant por desenho.

### A minha leitura, com as devidas reservas

Para **um estúdio**, provavelmente não é obrigatória. Mas:

1. O advogado tem de **verificar a lista da CNPD** de tratamentos
   sujeitos a AIPD, que é vinculativa e pode ir além do artigo 35.º,
   n.º 3.
2. Mesmo não sendo obrigatória, **fazer uma versão simplificada é
   barato e vale a pena**: obriga a escrever os riscos e as medidas, o
   que é exatamente o que uma inspeção pergunta. Boa parte do trabalho
   já está feita nos documentos 02 e 06.
3. **No dia em que houver um segundo estúdio, reavaliar.**

> **[ADVOGADO]** Decisão a tomar, com verificação da lista da CNPD.

### Se decidirem fazê-la, o que já existe

- Descrição sistemática do tratamento → documento 02
- Finalidades e fundamentos → documento 01, secção 5
- Necessidade e proporcionalidade → parcialmente nos documentos 01 e 06
- **Riscos** → por escrever
- **Medidas de mitigação** → documento 02, secção "Medidas de segurança"

Falta essencialmente a análise de riscos. Esboço dos que considero
relevantes, para não partir do zero:

| Risco | Probabilidade | Impacto | Medidas existentes |
|---|---|---|---|
| Aluno aceder a dados de saúde de outro | Baixa | Elevado | Regras no servidor por titular, testadas automaticamente |
| Instrutor registar avaliação sem consentimento | Baixa | Elevado | Recusado pelo servidor, não só pela interface; com teste |
| Fuga por credencial comprometida | Média | Elevado | Palavra-passe temporária obrigatória, reposição encerra sessões, verificação de integridade da app |
| Perda irreversível de dados | **Média** | Elevado | **Nenhuma — cópias de segurança por ativar** |
| Conservação para além do necessário | Média | Médio | Política escrita (documento 06); sem automatismo |
| Acesso indevido por ex-funcionário | Média | Elevado | Desativação e alteração de papéis com efeito imediato |

Dois riscos ficam com mitigação insuficiente e devem ser fechados antes
de haver dados reais: as **cópias de segurança** e a **eliminação
automática por prazo**.

---

## Parte B — Encarregado de Proteção de Dados (artigo 37.º)

### Quando é obrigatório

Três casos no n.º 1. O que nos interessa:

> alínea c) — *"as atividades principais do responsável [...] consistam
> em operações de tratamento em grande escala de categorias especiais de
> dados"*

Duas condições **cumulativas**: atividade principal **e** grande escala.

### Argumentos a favor de NÃO ser obrigatório

- **A atividade principal do estúdio é prestar treino**, não tratar
  dados de saúde. As avaliações são acessórias ao serviço — e o
  consentimento é opcional, o que confirma que o serviço existe sem
  elas.
- Não sendo "grande escala" (Parte A), falha a segunda condição.
- Falhando qualquer uma das duas, a alínea c) não se aplica.

### Argumentos a favor de SER obrigatório

- Pode argumentar-se que o acompanhamento físico personalizado — que
  depende das avaliações — é parte do núcleo da oferta de um
  "performance studio", e não um extra.
- Se crescer para vários estúdios, muda tudo.

### A minha leitura, com as devidas reservas

Provavelmente **não é obrigatório** para um estúdio único. Mas designar
um responsável interno é boa prática mesmo sem obrigação: alguém tem de
saber onde estão estes documentos, responder aos pedidos dentro do prazo
e conduzir a resposta a um incidente.

Se **não** for designado EPD formal, não pôr contactos de EPD na política
de privacidade — anunciar um que não existe é pior do que não ter.

> **[ADVOGADO]** Decisão a tomar. Se for designado, os contactos têm de
> constar da política de privacidade (documento 01, secção 1) e ser
> comunicados à CNPD.

---

## Resumo para decisão

| Pergunta | Leitura técnica | Decisão |
|---|---|---|
| AIPD obrigatória? | Provavelmente não, com um estúdio | [ADVOGADO] |
| Fazer AIPD simplificada mesmo assim? | Recomendo — barato e útil | [ADVOGADO] |
| EPD obrigatório? | Provavelmente não | [ADVOGADO] |
| Designar responsável interno? | Recomendo, com ou sem obrigação | [ADVOGADO] |
| Reavaliar com um 2.º estúdio? | **Sim, sem dúvida** | — |
