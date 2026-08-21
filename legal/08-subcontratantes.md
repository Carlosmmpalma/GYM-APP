# Subcontratantes e transferências

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

Artigo 28.º (subcontratantes) e capítulo V (transferências
internacionais).

---

## Quem é quem

- **Responsável pelo tratamento:** o estúdio. É quem decide que dados
  são recolhidos e para quê.
- **Subcontratante:** a Google, que aloja a infraestrutura e não decide
  nada sobre os dados.

Esta distinção não é formalidade: é o estúdio que responde perante os
titulares e perante a CNPD, mesmo quando a falha técnica é do
fornecedor.

---

## Subcontratante único: Google

Toda a infraestrutura assenta em serviços Firebase e Google Cloud. Não
há mais nenhum fornecedor com acesso a dados pessoais.

| Serviço | Para que serve | Que dados |
|---|---|---|
| **Cloud Firestore** | Base de dados principal | Todos os dados de negócio: perfis, marcações, avaliações, mensalidades |
| **Firebase Authentication** | Contas e sessões | Identificador, email (real ou sintético), resumo criptográfico da palavra-passe |
| **Cloud Functions** | Operações no servidor | Todos, em trânsito durante o processamento |
| **Cloud Storage** | Vídeos de exercícios | Vídeos da biblioteca (não são dados pessoais de alunos) |
| **Cloud Messaging (FCM)** | Avisos sobre aulas | Identificador de dispositivo |
| **Crashlytics** | Diagnóstico de erros | Modelo de dispositivo, versão do sistema, descrição da falha |
| **App Check** | Verificar que os pedidos vêm da app | Atestação do dispositivo |

**Localização:** Firestore e Cloud Functions em **europe-west1
(Bélgica)**. A região das funções está fixada no código
(`setGlobalOptions` em `firebase/functions/src/index.ts`) e não depende
de configuração na consola.

> **[ADVOGADO]** Confirmar a localização efetiva de **Authentication**,
> **Crashlytics** e **FCM** — nem todos permitem escolher região, e
> alguns são globais por natureza. Esta é uma diferença material para o
> capítulo V que eu não consigo garantir por leitura do código.

---

## O que é preciso ter, e ainda não está

### 1. Contrato de subcontratação (artigo 28.º, n.º 3)

A Google disponibiliza o *Cloud Data Processing Addendum*, que serve de
contrato de subcontratação. Não é automático: **tem de ser aceite** na
consola de administração do projeto.

- [ ] Aceitar o DPA na consola
- [ ] Guardar cópia ou registo da aceitação, com data

> **[ADVOGADO]** Verificar se o texto cobre as menções obrigatórias do
> n.º 3 (objeto, duração, natureza, finalidade, categorias, obrigações
> de confidencialidade, segurança, subcontratação ulterior, assistência
> nos direitos dos titulares, eliminação no fim, auditoria).

### 2. Entidade contratante

Para clientes no EEE, os serviços são geralmente prestados pela **Google
Ireland Limited**, o que mantém o contrato dentro da UE.

- [ ] Confirmar a entidade que consta do contrato após a criação do
      projeto

### 3. Subcontratantes ulteriores

A Google usa subcontratantes próprios e publica a lista. O artigo 28.º,
n.º 2 exige autorização — habitualmente dada de forma geral no DPA, com
direito de oposição a novas adições.

- [ ] Localizar a lista publicada e guardar referência
- [ ] Confirmar como são comunicadas as alterações

### 4. Transferências para países terceiros

Mesmo com armazenamento na UE, o suporte técnico pode implicar acesso a
partir de outros países.

- [ ] Confirmar o mecanismo previsto no DPA (Cláusulas
      Contratuais-Tipo e/ou decisão de adequação aplicável)
- [ ] Verificar se é exigível uma avaliação de impacto da transferência

> **[ADVOGADO]** O regime de transferências para os Estados Unidos tem
> mudado nos últimos anos e não posso garantir qual está em vigor à data
> em que isto for revisto. É um ponto a verificar na fonte, não a
> assumir daqui.

---

## Outros fornecedores a considerar

Nenhum destes existe hoje. Ficam listados porque cada um deles obriga a
voltar a este documento:

| Se um dia houver | Implicação |
|---|---|
| Fornecedor de SMS/email (recuperação de palavra-passe) | Novo subcontratante, com contactos dos alunos |
| Gateway de pagamentos | Novo subcontratante, com dados financeiros |
| Ferramenta de faturação integrada | Novo subcontratante, com identificação e NIF |
| Ferramenta de analítica de produto | Novo subcontratante; provavelmente exige consentimento próprio |
| Contabilista com acesso à aplicação | Destinatário ou subcontratante, conforme o enquadramento |

---

## Lista de verificação antes do arranque

- [ ] DPA aceite e cópia guardada
- [ ] Entidade contratante confirmada (Google Ireland Limited)
- [ ] Região do Firestore criada em `europe-west1` **[decisão
      definitiva — não se muda depois]**
- [ ] Localização dos restantes serviços confirmada e refletida na
      política de privacidade
- [ ] Lista de subcontratantes ulteriores localizada
- [ ] Mecanismo de transferência confirmado
- [ ] Política de privacidade atualizada com o que ficou apurado
