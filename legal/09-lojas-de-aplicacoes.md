# Declarações de privacidade nas lojas

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

A Apple e a Google exigem que se declare que dados a app recolhe. As
declarações **têm de bater certo com a política de privacidade** — uma
divergência é motivo de rejeição, e depois de publicada é motivo de
remoção.

Preenchi cada campo a partir do que o código faz. As respostas abaixo
são para copiar para os formulários.

---

## Apple — App Privacy (App Store Connect)

### Dados recolhidos e ligados à identidade do utilizador

| Categoria Apple | Recolhemos? | Para quê | Usado para rastreio? |
|---|---|---|---|
| Nome | **Sim** | Funcionalidade da app | Não |
| Endereço de email | **Sim** | Funcionalidade da app | Não |
| Número de telefone | **Sim** | Funcionalidade da app | Não |
| Morada física | **Sim** | Funcionalidade da app | Não |
| Outra informação de contacto | **Sim** (contacto de emergência) | Funcionalidade da app | Não |
| **Saúde e fitness — Saúde** | **Sim** | Funcionalidade da app | Não |
| **Saúde e fitness — Fitness** | **Sim** | Funcionalidade da app | Não |
| Informação financeira — outra | **Sim** (estado de mensalidades) | Funcionalidade da app | Não |
| Identificadores — ID de utilizador | **Sim** | Funcionalidade da app | Não |
| Diagnóstico — dados de falhas | **Sim** | Diagnóstico da app | Não |
| Diagnóstico — dados de desempenho | **Sim** | Diagnóstico da app | Não |
| Outros dados — data de nascimento, NIF | **Sim** | Funcionalidade da app | Não |

### Dados NÃO recolhidos

Localização, contactos do dispositivo, fotografias, histórico de
navegação, histórico de pesquisa, dados de publicidade, compras,
mensagens, áudio.

### Rastreio

**Não fazemos rastreio.** Nenhum dado é associado a dados de terceiros
para publicidade ou partilhado com data brokers. Não é necessária a
autorização de rastreio (ATT).

> **Ponto crítico:** declarar **"Saúde e fitness"** como recolhido e
> ligado à identidade. Omiti-lo seria falso, e a Apple é particularmente
> atenta a esta categoria. Preparar-se para justificar a finalidade na
> revisão.

---

## Google Play — Data safety

### Dados recolhidos

| Tipo | Recolhido | Partilhado | Obrigatório | Finalidade |
|---|---|---|---|---|
| Nome | Sim | Não | Sim | Funcionalidade da app; gestão da conta |
| Email | Sim | Não | Não | Funcionalidade da app |
| Telefone | Sim | Não | Não | Funcionalidade da app |
| Morada | Sim | Não | Não | Funcionalidade da app |
| **Informação de saúde** | Sim | Não | **Não** | Funcionalidade da app |
| **Informação de fitness** | Sim | Não | **Não** | Funcionalidade da app |
| Outra info. financeira | Sim | Não | Sim | Funcionalidade da app |
| ID de utilizador | Sim | Não | Sim | Funcionalidade da app; gestão da conta |
| Registos de falhas | Sim | Não | Não | Diagnóstico |
| Diagnóstico | Sim | Não | Não | Diagnóstico |

**"Obrigatório: Não" nos dados de saúde e fitness é a declaração
correta**, e é a que reflete o desenho da aplicação: o consentimento é
opcional e recusá-lo não impede usar o serviço. Declarar "obrigatório"
seria contradizer o que a app faz e o fundamento legal em que assenta.

### Práticas de segurança

- [x] Dados cifrados em trânsito
- [x] O utilizador pode pedir a eliminação dos dados
- [x] Existe compromisso com a Play Families Policy — [ADVOGADO: só se
      aceitarem menores]

### Eliminação de conta

A Google exige um **caminho para pedir a eliminação da conta**, incluindo
um endereço web acessível sem instalar a app.

**Situação atual:** a app não tem eliminação self-service — é pedida ao
estúdio, com verificação presencial de identidade (documento 04).

- [ ] **[PREENCHER]** Criar uma página web com instruções de como pedir
      a eliminação e o contacto do estúdio, e indicar o endereço no
      formulário.

> Esta é uma exigência da Google que pode bloquear a publicação. A
> verificação presencial é defensável e mais protetora do titular, mas
> tem de existir um caminho documentado e alcançável a partir da web.

---

## Coerência — verificar antes de submeter

- [ ] O que está declarado é exatamente o que a política de privacidade
      diz (documento 01, secção 3)
- [ ] O endereço da política de privacidade está preenchido nas duas
      lojas e é acessível publicamente
- [ ] Ambas declaram dados de saúde
- [ ] Nenhuma declara rastreio ou publicidade
- [ ] O caminho de eliminação de conta existe e está indicado
- [ ] Se a app passar a aceitar menores, rever as duas declarações e as
      políticas para famílias

---

## Se um dia acrescentarem algo

Qualquer um destes obriga a rever as declarações **antes** de publicar a
versão nova:

- pagamentos dentro da app;
- integração com o Apple Health ou o Google Fit;
- fotografias de perfil ou de progresso (dados biométricos — patamar
  ainda mais exigente);
- analítica de produto ou qualquer forma de publicidade;
- partilha de dados com terceiros, seja para que fim for.
