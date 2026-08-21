# Plano de resposta a violação de dados

**RASCUNHO PARA REVISÃO JURÍDICA.** Ver [README](README.md).

Artigos 33.º e 34.º do RGPD. Documento interno.

---

## O prazo que manda em tudo

**72 horas** para notificar a CNPD, a contar do momento em que se toma
conhecimento — não do momento em que se percebe a extensão. Se passar de
72 horas, a notificação tem de vir acompanhada da justificação do atraso.

Não é preciso saber tudo para notificar. É preciso notificar e completar
depois (artigo 33.º, n.º 4). **Atrasar por estar a investigar é o erro
mais comum.**

---

## O que conta como violação

Não é só "fomos pirateados". Qualquer destes é uma violação:

- Alguém do estúdio partilhar credenciais e outra pessoa aceder a dados
  de alunos.
- Um telemóvel ou portátil com sessão aberta ser perdido ou roubado.
- Uma exportação de dados ser enviada para o destinatário errado.
- Um erro nas regras de acesso expor dados de um aluno a outro.
- Uma eliminação acidental de dados sem forma de os recuperar
  (**violação de disponibilidade** — conta na mesma).
- Um antigo funcionário manter acesso depois de sair.

---

## Passo 1 — Conter (imediato)

Antes de investigar, parar a hemorragia:

| Situação | Ação imediata |
|---|---|
| Conta comprometida | Repor a palavra-passe na app — encerra as sessões abertas noutros dispositivos |
| Ex-funcionário com acesso | Desativar o staff e retirar-lhe os papéis |
| Regra de acesso mal publicada | Republicar as regras corretas |
| Suspeita de acesso indevido generalizado | Contactar o suporte do fornecedor e considerar suspender o acesso à aplicação |

Anotar a hora de cada ação. Vai ser preciso.

## Passo 2 — Avaliar (primeiras horas)

Responder a estas perguntas, por escrito:

1. **O que aconteceu**, e quando começou.
2. **Que categorias de dados** foram afetadas. Distinguir explicitamente
   se incluem **dados de saúde** — muda a avaliação de risco.
3. **Quantas pessoas**, aproximadamente.
4. **Que tipo de violação**: confidencialidade (alguém viu),
   integridade (alguém alterou), disponibilidade (perdeu-se).
5. **Consequências prováveis** para os titulares.
6. **O que já foi feito** para conter e mitigar.

## Passo 3 — Notificar a CNPD (até 72 horas)

Pelo formulário da CNPD, em [www.cnpd.pt](https://www.cnpd.pt).

Só é dispensável se for **improvável** que a violação resulte em risco
para os direitos e liberdades dos titulares. Sendo dados de saúde, essa
improbabilidade é difícil de sustentar.

Havendo dúvida, notificar. A notificação desnecessária tem custo zero; a
omissão tem coima.

**Mesmo que não se notifique, documentar** — o artigo 33.º, n.º 5 obriga
a registar todas as violações, incluindo as não notificadas, com a
fundamentação da decisão.

## Passo 4 — Informar os titulares (artigo 34.º)

Obrigatório quando a violação for suscetível de implicar um **risco
elevado**. Com dados de saúde envolvidos, presumir que sim salvo prova
em contrário.

Dispensado se os dados estavam cifrados de forma que os torne
ininteligíveis a quem lhes acedeu, ou se foram tomadas medidas
posteriores que afastem o risco elevado.

**Em linguagem clara e simples** — não em juridiquês. Tem de dizer:

- o que aconteceu;
- que dados foram afetados;
- as consequências prováveis;
- o que o estúdio fez e vai fazer;
- o que a pessoa deve fazer (por exemplo, mudar a palavra-passe se a
  reutilizar noutros sítios);
- contacto para esclarecimentos.

### Modelo

> **Assunto: Comunicação sobre um incidente com os seus dados**
>
> [Nome],
>
> Escrevemos para o(a) informar de um incidente ocorrido em [data], que
> afetou dados pessoais tratados pelo [estúdio].
>
> **O que aconteceu:** [descrição factual, sem atenuantes].
>
> **Que dados foram afetados:** [lista concreta. Se incluir dados de
> saúde, dizê-lo expressamente].
>
> **O que isto pode significar para si:** [consequências prováveis, sem
> minimizar].
>
> **O que já fizemos:** [medidas de contenção, com datas].
>
> **O que lhe pedimos que faça:** [ações concretas, se aplicável].
>
> Lamentamos sinceramente. Pode contactar-nos em [contacto] para
> qualquer esclarecimento, e tem o direito de apresentar reclamação à
> Comissão Nacional de Proteção de Dados.
>
> [Responsável] · [data]

## Passo 5 — Registar e corrigir

Guardar o registo completo: cronologia, avaliação, decisões tomadas e
respetiva fundamentação, comunicações enviadas.

Corrigir a causa. Se foi uma falha nas regras de acesso, acrescentar um
**teste automatizado** que a apanhe — a suite existente é o sítio certo,
e é assim que uma falha deixa de poder voltar em silêncio.

---

## Contactos a preencher antes de precisar deles

| | |
|---|---|
| Responsável interno pela resposta | [PREENCHER] |
| Suplente | [PREENCHER] |
| Apoio jurídico | [PREENCHER] |
| Apoio técnico | [PREENCHER] |
| CNPD | www.cnpd.pt · [PREENCHER: telefone atual] |
| Suporte do fornecedor (Google Cloud) | [PREENCHER: canal contratado] |

> **[ADVOGADO]** Confirmar o formulário e o canal de notificação atuais
> da CNPD, e se há particularidades para dados de saúde.

---

## Uma nota honesta sobre a capacidade atual

Enquanto as cópias de segurança não estiverem ativas (ver LANCAMENTO.md,
secção 4), o estúdio **não tem como recuperar dados eliminados por
erro** — e uma eliminação acidental é uma violação de disponibilidade,
notificável como qualquer outra.

É o ponto mais fraco do plano, e resolve-se com dois cliques na consola
antes de haver dados reais.
