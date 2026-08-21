# Registo de Atividades de Tratamento

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

Artigo 30.º do RGPD. A dispensa para entidades com menos de 250
trabalhadores (n.º 5) **não se aplica aqui**: cai por tratar dados do
artigo 9.º e por o tratamento não ser ocasional.

Documento interno. Deve ser mantido atualizado e apresentado à CNPD se
solicitado.

---

## Identificação

| | |
|---|---|
| **Responsável pelo tratamento** | [PREENCHER: denominação social] |
| **NIPC** | [PREENCHER] |
| **Sede** | [PREENCHER] |
| **Contacto** | [PREENCHER: email/telefone] |
| **Encarregado de Proteção de Dados** | [ADVOGADO — ver documento 07] |
| **Data deste registo** | [PREENCHER] |
| **Última atualização** | [PREENCHER] |

---

## Tratamento 1 — Gestão de alunos e prestação do serviço

**Finalidade.** Gerir a inscrição, dar acesso à aplicação, permitir
marcar e cancelar sessões, controlar o limite semanal do plano, registar
presenças.

**Categorias de titulares.** Alunos inscritos no estúdio.

**Categorias de dados.** Nome, número de sócio, telefone, email, data de
nascimento, morada, NIF, contacto de emergência, estado ativo/inativo;
marcações (data, hora, serviço, origem, cancelamentos); presenças e
faltas; utilização semanal por serviço.

**Fundamento.** Artigo 6.º, n.º 1, alínea b) — execução do contrato.
Quanto ao contacto de emergência, alínea d) — interesse vital.

**Destinatários.** Gestor e instrutores do estúdio. Google Ireland
Limited como subcontratante (documento 08).

**Transferências para países terceiros.** Armazenamento na UE
(europe-west1). Acesso pontual de suporte pela subcontratante coberto
pelo respetivo contrato e Cláusulas Contratuais-Tipo.

**Prazo de conservação.** Documento 06.

---

## Tratamento 2 — Gestão contratual e de mensalidades

**Finalidade.** Registar o plano subscrito, o preço acordado e o estado
de cada mensalidade; suportar a faturação.

**Categorias de titulares.** Alunos inscritos.

**Categorias de dados.** Plano, serviços incluídos, preço acordado,
moeda, datas de início e fim, estado da subscrição; por mês: estado da
mensalidade, valor, data e autor de cada alteração; NIF.

**Fundamento.** Artigo 6.º, n.º 1, alínea b); e alínea c) — obrigação
legal, quanto à conservação de documentos de suporte à contabilidade.

**Destinatários.** Gestor do estúdio (os instrutores **não** têm acesso
a dados financeiros — está garantido nas regras do servidor).
Contabilista [PREENCHER: se aplicável]. Google Ireland Limited.

**Prazo de conservação.** Prazo legal de conservação fiscal — ver
documento 06. Em caso de pedido de apagamento, o registo é **anonimizado
em vez de eliminado**.

---

## Tratamento 3 — Avaliação física e acompanhamento do treino

> **Este é o tratamento sensível.** Envolve dados do artigo 9.º.

**Finalidade.** Avaliar a condição física, elaborar e ajustar o plano de
treino, acompanhar a evolução.

**Categorias de titulares.** Alunos que tenham dado consentimento
explícito.

**Categorias de dados (artigo 9.º — dados relativos à saúde).** Idade,
peso, altura, percentagem de massa gorda, massa muscular, gordura
visceral, metabolismo basal, percentagem de água, idade metabólica,
pressão arterial, perímetro da cintura e abdominal, níveis de força
(membros superiores, inferiores, core), flexibilidade e resistência.
Plano de treino (exercícios, séries, repetições) e histórico de cargas.

**Fundamento.** Artigo 9.º, n.º 2, alínea a) — **consentimento
explícito** do titular. Conjugado com o artigo 6.º, n.º 1, alínea a).

**Como o consentimento é obtido e demonstrado.** Documento 03. Registo
com data do servidor, versão do texto e histórico imutável de cada
alteração.

**Destinatários.** Gestor e instrutores do estúdio. Google Ireland
Limited.

**Prazo de conservação.** Documento 06.

**Nota técnica relevante.** A ausência de consentimento é aplicada pelo
**servidor**: sem ele, nem um instrutor autenticado consegue escrever
uma avaliação, mesmo contornando a aplicação. Existe teste automatizado
que o demonstra.

---

## Tratamento 4 — Gestão de pessoal com acesso à aplicação

**Finalidade.** Dar acesso à aplicação a instrutores e gestores, com as
permissões correspondentes.

**Categorias de titulares.** Instrutores e gestores.

**Categorias de dados.** Nome, email profissional, telefone, data de
nascimento, papéis atribuídos, modalidades que leciona, estado
ativo/inativo, registo de alterações de papéis e de reposições de
palavra-passe (data e autor).

**Fundamento.** Artigo 6.º, n.º 1, alínea b) — execução do contrato de
trabalho ou de prestação de serviços.

**Destinatários.** Gestor do estúdio. Google Ireland Limited.

**Prazo de conservação.** Documento 06.

---

## Tratamento 5 — Comunicações operacionais

**Finalidade.** Avisar os alunos de alterações às sessões que têm
marcadas (cancelamento de aula, remoção de uma sessão, desativação de um
instrutor).

**Categorias de dados.** Identificador de dispositivo para notificações
(token), associado ao utilizador.

**Fundamento.** Artigo 6.º, n.º 1, alínea b) — execução do contrato. São
comunicações operacionais sobre o serviço contratado, **não marketing**.

> **[ADVOGADO]** Se algum dia forem enviadas comunicações promocionais,
> passam a exigir consentimento próprio e mecanismo de oposição. A
> aplicação hoje **não** tem essa funcionalidade.

**Prazo de conservação.** O token é substituído pelo dispositivo e
eliminado com a conta.

---

## Tratamento 6 — Segurança e diagnóstico técnico

**Finalidade.** Prevenir abuso e acessos indevidos; identificar e
corrigir falhas da aplicação.

**Categorias de dados.** Registos de limitação de pedidos por
utilizador; relatórios de erro com modelo de dispositivo, versão do
sistema e descrição técnica da falha.

**Fundamento.** Artigo 6.º, n.º 1, alínea f) — interesse legítimo em
manter o serviço seguro e funcional. O interesse dos titulares não
prevalece: os dados são técnicos, mínimos e não usados para os
caracterizar.

**Destinatários.** Google Ireland Limited (Crashlytics).

**Prazo de conservação.** Conforme as definições do serviço de
diagnóstico; os registos de limitação de pedidos são efémeros (janelas
de minutos).

> **[ADVOGADO]** Confirmar se o diagnóstico de erros na versão **web**
> exige consentimento prévio à luz do regime do artigo 5.º, n.º 3 da
> Diretiva ePrivacy (armazenamento no equipamento do utilizador). Se
> sim, é preciso um mecanismo de consentimento próprio, que hoje não
> existe.

---

## Medidas de segurança (artigo 32.º)

Descrição factual do que está implementado e testado.

### Controlo de acesso

- Autenticação individual. Alunos por número de sócio, pessoal por email.
- Papéis (aluno, instrutor, gestor) inscritos no próprio token de
  autenticação e verificados **no servidor** em cada operação.
- **Isolamento entre ginásios**: os dados de cada estúdio estão
  segregados e o pertencimento é verificado em todas as leituras e
  escritas. Verificado por testes automatizados dedicados.
- Regra de menor privilégio aplicada por categoria e por titular:
  - os instrutores não acedem a dados financeiros;
  - **um aluno só lê o seu próprio perfil** — não alcança o nome, NIF,
    morada nem contactos de mais ninguém;
  - **um aluno não vê quem está inscrito numa aula**, apenas quantos
    lugares estão ocupados;
  - um aluno não lê as subscrições nem os preços acordados de outro.

### Autenticação

- Palavras-passe guardadas apenas em forma cifrada irreversível — nem o
  estúdio nem o fornecedor as conseguem ler.
- Palavras-passe temporárias de obrigatória alteração no primeiro acesso.
- Reposição de palavra-passe encerra as sessões abertas noutros
  dispositivos.
- Alteração de permissões força a renovação imediata do token.

### Integridade das operações

- Operações críticas (marcações, criação de contas, apagamento) correm
  no servidor, em transação, e não no dispositivo do utilizador.
- Limitação de pedidos por utilizador e operação, contra abuso e uso
  automatizado.
- Verificação de integridade da aplicação (App Check), para impedir que
  as funções sejam chamadas fora da app.

### Dados em trânsito e em repouso

- Comunicação exclusivamente por canal cifrado (HTTPS/TLS).
- Cifragem em repouso assegurada pela infraestrutura da subcontratante.

### Registo e auditoria

- Alterações a dados sensíveis registam autor e data: estado de
  mensalidades, alterações de papéis, reposições de palavra-passe,
  anonimizações.
- Histórico imutável de consentimentos (append-only).

### Resiliência

- [PENDENTE] Recuperação a um ponto no tempo (PITR) e exportações
  diárias — **ainda por ativar**; ver LANCAMENTO.md, secção 4. Até lá,
  não existe capacidade de restaurar dados eliminados por erro.

> **[ADVOGADO]** Este ponto está por resolver e é material para o artigo
> 32.º, n.º 1, alínea c). Deve ficar sanado antes de haver dados reais.

### Verificação regular (artigo 32.º, n.º 1, alínea d)

- Suite de testes automatizados que verifica as regras de acesso contra
  um servidor real a cada alteração ao código: 177 testes, incluindo
  isolamento entre ginásios, concorrência e aplicação do consentimento.
