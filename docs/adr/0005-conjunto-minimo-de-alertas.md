# ADR 0005: Conjunto mínimo de alertas para um ambiente efêmero

## Status

Aceito — 2026-09-09. Atualizado em 2026-11-15: monitores por serviço e da solução distribuída.

## Contexto

O plano exploratório deste repositório listava quinze candidatos a monitor, para uma solução com um só
serviço. Nove sobreviveram. Quando a solução passou a quatro serviços — `work-order` (ordens de serviço),
`identity` (usuários e login), `billing` (orçamentos e cobranças) e `inventory` (peças e estoque) — ligados
por filas e por Sagas (transações que atravessam serviços e são desfeitas quando um passo falha), o mesmo
critério foi aplicado aos sinais novos. Este ADR registra o critério e cada recusa, porque a pergunta "por que não temos um alerta para X?" vai voltar — e a
discussão precisa partir do motivo, não do zero.

Três fatos decidem quase tudo:

1. **O ambiente é efêmero.** O laboratório é ligado sob demanda e destruído ao final de cada sessão. Qualquer
   alerta que dependa de *presença* de dado dispara ao fim de toda sessão.
2. **O tráfego é esporádico.** Não há carga sustentada: há rajadas de demonstração separadas por horas de
   silêncio. Taxas calculadas sobre volume baixo são ruído.
3. **O time tem quatro pessoas, e não há plantão.** Todo alerta vai para os mesmos quatro endereços de e-mail.
   O orçamento de atenção é pequeno e não renovável: alertas que não exigem ação treinam o time a ignorar os
   que exigem.

O critério que sai daí é um só, e é aplicado a cada candidato:

> **O que a pessoa faz ao receber este e-mail?** Se a resposta for "olha e volta a dormir", é um widget de
> dashboard, não um monitor.

## Decisão

**Trinta e quatro monitores, de quinze tipos**, listados e detalhados em [Monitores](../monitors.md). Os seis
primeiros se repetem por serviço e o sétimo por função Lambda — por isso a contagem passa do número de tipos:

| Monitor | Sintoma | Quantos | Prioridade |
| --- | --- | ---: | --- |
| Disponibilidade externa | Rota pública de saúde do serviço indisponível (verificação externa) | 4 | P1 |
| Serviço · Erros 5xx | Erros 5xx acima do limite, por rota | 4 | P2 |
| Serviço · Latência p95 | Latência p95 acima do alvo | 4 | P3 |
| Pod · Memória | Memória do pod próxima do limite | 4 | P2 |
| Pod · Reinícios | Reinícios de contêiner | 4 | P3 |
| Serviço · Health check | Dependência do serviço degradada | 4 | P3 |
| Lambda · Erros de execução | Erros de plataforma da customer-auth ou da notification | 2 | P2 |
| Ordens de Serviço | Falhas no fluxo de ordens de serviço, no work-order e no billing | 1 | P2 |
| Lambda notification · E-mail | Falha de envio de e-mail, por motivo e tipo de e-mail | 1 | P4 |
| Mensageria · DLQ | Mensagem desistida pelo consumidor, que deixa uma ordem de serviço parada | 1 | P2 |
| Mensageria · DLQ sem tipo | Mensagem sem envelope válido desistida pelo consumidor, que não volta com redrive | 1 | P2 |
| Mensageria · Outbox | Relay do outbox parado: as mensagens de um serviço não saem | 1 | P2 |
| Pagamentos · Webhook | Notificações do Mercado Pago recusadas por assinatura inválida | 1 | P2 |
| Sagas · Compensações | Aprovações de orçamento desfeitas acima do esperado | 1 | P3 |
| Cache · Limpeza | Chave de cache não apagada depois de uma escrita | 1 | P3 |

**Nenhum monitor tem `notify_no_data` ligado**, e é essa opção que torna seguro desligar o ambiente.

Os monitores de métrica de contagem esparsa — erros 5xx, falhas no fluxo de ordens de serviço, erros das
Lambdas e compensações, métricas que só recebem ponto quando o evento acontece — envolvem a consulta em
`default_zero()`: a janela sem ponto avalia como zero, e o monitor resolve em vez de manter o último estado.
Sem a função, o monitor de compensações ficou em alerta depois que a janela esvaziou, e um monitor em alerta
não notifica a ocorrência seguinte. Nos monitores de métrica contínua, com o ambiente desligado, o destino
mantém o último estado ou mostra `No Data`; nenhum notifica, por causa de `notify_no_data = false`.

**Nenhum monitor tem `renotify_interval`.** Não há plantão para escalar, e repetir o alerta a cada N minutos
transforma a caixa de entrada em algo que se filtra.

### Contagem, não taxa, nos monitores de erro, de envio de e-mail e de compensação

Com tráfego esporádico, uma taxa dispara com "1 erro em 3 requisições" — que é uma tarde normal de
demonstração. As taxas permanecem nos dashboards, onde informam sem acordar ninguém.

**Gatilho de migração para taxa**: volume sustentado acima de 10 req/min.

O mesmo vale para as Sagas. A arquitetura da solução pedia um alerta de **taxa** de compensação; com este
volume, uma taxa dispara com uma única Saga desfeita. O monitor conta compensações em número absoluto — mais
de uma em uma hora — e a taxa fica no dashboard de Sagas. A divergência é deliberada e fica registrada aqui.

**Só a aprovação de orçamento (`QUOTE_APPROVAL`) entra no monitor.** A Saga de pagamento (`PAYMENT`) termina
compensada quando a cobrança é recusada, expira ou é cancelada, que são desfechos normais do pagamento: dois
cartões recusados na janela disparariam o alerta.

| Alternativa avaliada | Por que não |
| --- | --- |
| **Monitor por taxa de compensação** | Dispara com uma amostra |
| **Os dois tipos de Saga no monitor** | Ruído: cobrança recusada não é defeito |
| **Monitor de log sobre `saga.compensated`, excluindo os motivos de pagamento e agrupado por tipo e motivo** | O alerta diria o motivo, mas a contagem da métrica já responde se há compensação demais, e o motivo está no dashboard de Sagas |

**Gatilho para reabrir**: a compensação de `PAYMENT` por `WORK_ORDER_NOT_PAYABLE` (a ordem de serviço fora do
status de cobrança) se repetir. Ela indica defeito, não desfecho do cliente, e pediria o monitor de log.

### Limiares provisórios

Três limiares novos não têm dado observado e estão declarados como provisórios, com a origem na descrição da
variável: o relay do outbox (10 falhas em 5 minutos; uma falha persistente gera mais de 120, uma isolada gera
1), o webhook com assinatura inválida (3 recusas em 15 minutos; uma chave errada recusa todas as notificações,
e o Mercado Pago as reenvia) e as compensações (1 em 1 hora). Os de DLQ e de limpeza do cache são zero, porque
cada ocorrência é uma ordem de serviço parada ou um dado errado servido ao usuário.

### A redundância entre os dois monitores de erro é assumida

Os monitores de erros 5xx e de ordens de serviço disparam juntos numa indisponibilidade total do work-order ou
do billing, e isso **não é um defeito a corrigir**. São leituras distintas — *"o serviço está falhando"* e *"o
fluxo de negócio está quebrado"* — para públicos distintos, e a segunda nomeia o impacto que a primeira não
nomeia. As demais sobreposições — DLQ e e-mail, outbox e DLQ, webhook por log e por métrica, health check e
erros — estão declaradas em [Monitores](../monitors.md#sobreposições-assumidas).

| Alternativa avaliada | Por que não |
| --- | --- |
| **Monitor composto** (um `AND NOT` do outro) | Cerimônia desproporcional: acrescenta um recurso, uma indireção e uma classe nova de defeito para evitar um e-mail duplicado ocasional |
| **Um único monitor agrupado por rota** | Perderia a nomeação do impacto de negócio, que é o requisito do monitor de ordens de serviço |
| **Excluir as rotas de negócio do escopo do monitor de erros 5xx** | Uma falha geral deixaria de aparecer no alerta do serviço, que é justamente o alerta que se olha primeiro |

## Alertas recusados

| Recusado | Motivo | Gatilho para reabrir |
| --- | --- | --- |
| **Coleta interrompida** | Seu disparo seria **garantido** ao final de toda sessão do laboratório. É o exemplo mais claro do critério: o alerta seria disparado por um evento planejado | O ambiente passar a ser permanente |
| **CPU alta** | Com autoescalonamento mirando 70 % de CPU, "CPU alta" é o mecanismo **funcionando**. Alertar sobre isso é alertar sobre o sucesso | Estrangulamento sustentado correlacionado com a latência de um serviço |
| **Estrangulamento de CPU** | É o sinal acionável que "CPU alta" não é — mas, sem evidência de que ele preceda degradação percebida nesta aplicação, seria um alerta em busca de um problema. Fica no dashboard de Kubernetes | A latência de um serviço disparar com estrangulamento como causa recorrente |
| **Nenhuma OS criada em 24 h** | Dispararia todo dia. Num ambiente ligado algumas horas por semana, "nenhuma ordem criada" é o estado normal | Ambiente permanente com uso real |
| **Permanência média por status acima de X** | Não existe acordo de negócio que defina o X. Inventar um limiar produz um alerta permanentemente vermelho ou permanentemente verde, e os dois são inúteis | O negócio declarar um acordo de nível de serviço |
| **Latência de banco em monitor próprio** | Sem latência alta no serviço, latência de banco alta não é incidente. Com ela, o monitor de latência já disparou e o dashboard do serviço mostra a causa no grupo Banco | — |
| **Descarte de span pelo canal `diag` do OTel** | Descarte por fila cheia é comportamento **declarado como aceito** no ADR 0005 do work-order. Alertar contrariaria a decisão de origem — e o alerta certo, se um dia for necessário, pertence àquele repositório | O work-order reabrir aquela decisão |
| **Qualquer monitor sobre `kubernetes_state.*`** | Não existe: não há Cluster Agent na instalação (L1) | Instalar o Cluster Agent |
| **Timeouts e falta de memória da Lambda, em monitores próprios** | Ambos incrementam `aws.lambda.enhanced.errors`, que o monitor de erros de execução já observa. Seriam três e-mails para o mesmo evento | — |
| **Objetivo de nível de serviço** | Janela fixa de 30 dias sobre um ambiente desligado na maior parte do tempo produz um número sem significado | Ambiente permanente |
| **Profundidade de fila e idade da mensagem mais antiga** | São métricas do SQS, que exigem a integração AWS do Datadog, bloqueada no laboratório. A DLQ é vigiada pelo evento que o consumidor registra ao desistir da mensagem | A integração AWS passar a existir |
| **Cobrança expirada, recusada ou cancelada** | Desfecho normal do pagamento. Fica no dashboard de Pagamentos | — |
| **Compensações da Saga de pagamento** | Consequência das mesmas cobranças. Ficam no dashboard de Sagas | Compensação por `WORK_ORDER_NOT_PAYABLE` se repetir |

## Limiares: origem declarada

**Os limiares de latência são valores de percepção de usuário, não percentis observados**, e estão declarados como
tais. O único dado medido — p95 de 23,5 ms no compose local, ADR 0005 do work-order — não representa produção.

Os limiares atuais são variáveis em `terraform/variables.tf`, com valores em
`terraform/terraform.tfvars`. O [Runbook](../runbook.md) descreve como comparar esses valores com p95 e p99
observados sem editar as consultas.

## Consequências

- Quatro e-mails por evento, para quatro pessoas, e nada além disso. O orçamento de atenção é gasto só onde há
  ação.
- **Trinta e quatro monitores não cobrem tudo**, e não deveriam. As lacunas conhecidas — estado do cluster, API
  Gateway, RDS, profundidade de fila, traces da customer-auth — estão documentadas como limitações em
  [Observabilidade](../observability.md#3-limitações), com a causa de cada uma.
- **Os monitores sobre eventos de falha não podem ser verificados de ponta a ponta** sem provocar o evento na
  origem: `notification.failed`, `health.degraded`, `messaging.message.dead_lettered`,
  `messaging.outbox.publish_failed`, `payment.webhook.invalid_signature` e `cache.invalidation_failed`, e a
  métrica `oficina.saga.finished` com `oficina.saga.outcome:compensated`, só existem quando a falha acontece.
  Os nomes foram conferidos nos catálogos dos serviços, e a verificação com a falha provocada é feita com o
  ambiente no ar.
- **Os monitores de contagem esparsa dependem de `default_zero()` para resolver.** Sem a função, uma janela sem
  ponto mantém o último estado, e um monitor que ficou em alerta não notifica a ocorrência seguinte. Com ela,
  esses monitores ficam `OK` na operação normal, inclusive os de erros das Lambdas, cuja métrica
  `aws.lambda.enhanced.errors` só passa a existir na primeira falha.

## Gatilho de reavaliação

O ambiente passar a ser permanente reabre, de uma vez: coleta interrompida, objetivo de nível de serviço,
"nenhuma OS criada em 24 h" e a migração de contagem para taxa. Quatro decisões, um único fato.
