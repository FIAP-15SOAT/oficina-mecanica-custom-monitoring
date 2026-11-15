# Monitores

Trinta e três monitores na conta: 29 recursos `datadog_monitor`, em nove arquivos `terraform/monitors_*.tf`, e
os 4 monitores que os testes sintéticos de `terraform/synthetics.tf` criam no destino, um por teste. Este
documento é a fonte única das consultas de alerta.

| Monitor | Quantos | Prioridade | Arquivo |
| --- | ---: | --- | --- |
| [Disponibilidade externa `<contexto>`](#disponibilidade-externa-contexto--rota-pública-indisponível) | 4, um por serviço | P1 | `synthetics.tf` |
| [Serviço `<contexto>` · Erros 5xx acima do limite](#serviço-contexto--erros-5xx-acima-do-limite) | 4 | P2 | `monitors_service.tf` |
| [Serviço `<contexto>` · Latência p95 acima do alvo](#serviço-contexto--latência-p95-acima-do-alvo) | 4 | P3 | `monitors_service.tf` |
| [Ordens de Serviço · Falhas no processamento](#ordens-de-serviço--falhas-no-processamento) | 1 | P2 | `monitors_work_orders.tf` |
| [Pod `<contexto>` · Memória próxima do limite](#pod-contexto--memória-próxima-do-limite) | 4 | P2 | `monitors_kubernetes.tf` |
| [Pod `<contexto>` · Reinícios de contêiner](#pod-contexto--reinícios-de-contêiner) | 4 | P3 | `monitors_kubernetes.tf` |
| [Lambda `<função>` · Erros de execução](#lambda-função--erros-de-execução) | 2, um por Lambda | P2 | `monitors_lambda.tf` |
| [Lambda notification · Falha de envio de e-mail](#lambda-notification--falha-de-envio-de-e-mail) | 1 | P4 | `monitors_integrations.tf` |
| [Serviço `<contexto>` · Health check degradado](#serviço-contexto--health-check-degradado) | 4 | P3 | `monitors_integrations.tf` |
| [Mensageria · Mensagem na DLQ](#mensageria--mensagem-na-dlq) | 1 | P2 | `monitors_messaging.tf` |
| [Mensageria · Relay do outbox parado](#mensageria--relay-do-outbox-parado) | 1 | P2 | `monitors_messaging.tf` |
| [Pagamentos · Webhook com assinatura inválida](#pagamentos--webhook-com-assinatura-inválida) | 1 | P2 | `monitors_payments.tf` |
| [Sagas · Compensações da aprovação de orçamento](#sagas--compensações-da-aprovação-de-orçamento) | 1 | P3 | `monitors_sagas.tf` |
| [Cache · Falha na limpeza do cache](#cache--falha-na-limpeza-do-cache) | 1 | P3 | `monitors_cache.tf` |

`<contexto>` é cada chave do mapa de serviços (`work-order`, `identity`, `billing`, `inventory`) e `<função>`,
cada chave do mapa de Lambdas (`customer-auth`, `notification`) — ver
[Infraestrutura](terraform.md#os-mapas-de-serviços-e-de-lambdas).

Os nomes dos sinais e o motivo de cada ausência estão em [Observabilidade](observability.md), citados por
sigla. As consultas dos widgets estão em [Dashboards](dashboards.md) e não se repetem aqui. O que fazer quando
cada um dispara está no [Runbook](runbook.md), e a mensagem de todo alerta leva o link do item.

---

## Configuração comum

Aplicada a todos, e cada item tem razão:

| Opção | Valor | Por quê |
| --- | --- | --- |
| `notify_no_data` | **`false`** em todos | O laboratório é ligado sob demanda e destruído ao final (L10). Notificar por ausência de dado dispararia dezenas de alertas ao fim de toda sessão. Também protege o serviço que não emite um sinal: o identity não consome fila e nunca terá série de DLQ |
| `renotify_interval` | `0` | Não há plantão. Repetir o alerta a cada N minutos treina o time a silenciar a caixa de entrada |
| `notify_audit` | `false` | Mudança de definição do monitor é vista no Pull Request, não por e-mail |
| `include_tags` | `true` | O e-mail carrega as tags do grupo afetado |
| `require_full_window` | `true` **nos monitores de contagem** | Contagem parcial de janela produz falso negativo. **Exceções: erros das Lambdas e compensações de Saga**, cujas métricas só passam a existir no primeiro evento (L14) |
| `new_group_delay` | 300 s nos monitores agrupados (600 s nos reinícios) | Um grupo recém-observado — uma rota nova, um pod novo, um serviço recém-implantado — não dispara antes de ter janela cheia |
| `enable_logs_sample` | `true` nos monitores de log | O e-mail traz uma amostra das linhas que dispararam o alerta, com o erro e o `trace_id` |
| `escalation_message` | não usado | Não há plantão para escalar |
| `notify_by` | **não usado** | O destino recusa uma lista que cubra *todos* os agrupamentos da consulta — `The notify_by list may not include all of the query's group keys`. O comportamento pretendido, uma notificação por rota, por pod ou por serviço afetado, **já é o padrão** de um monitor agrupado |
| `tags` | `project:oficina-mecanica`, `managed-by:terraform`, `env:…` e, quando o monitor é de um componente, `service:…` | Ver [Convenções](conventions.md#tags-dos-recursos-criados) |

**O que acontece quando não há evento.** Há dois casos, e eles são diferentes:

- **A série existe e a janela está vazia** → avalia como **zero**. É o caso de um monitor de log cuja consulta
  já retornou algo antes.
- **A série não existe** — nenhum 5xx jamais ocorreu, nenhum erro de plataforma na Lambda — → o destino
  reporta **`No Data`**, e não zero. Verificado na conta: os monitores de erros 5xx, de falhas no fluxo de
  ordens de serviço e de erros da Lambda ficam em `No Data` com a solução saudável.

**Nos dois casos nada é notificado, e é `notify_no_data = false` que garante isso** — não a aritmética da
contagem. É essa opção, e só ela, que torna seguro desligar o ambiente.

### Estrutura da mensagem

Uma só, em `local.monitor_message`, renderizada por `templatestring` em cada monitor:

```
{{#is_alert}}🔴 **<sintoma>**<sufixo do grupo>{{/is_alert}}
{{#is_warning}}🟡 **<sintoma atenuado>**<sufixo do grupo>{{/is_warning}}

Serviço: `<serviço>` · Ambiente: `<ambiente>`
Observado: **{{value}}** <unidade> (limite: {{threshold}}) na janela de <N>
Desde: {{first_triggered_at}}

[Dashboard](<dashboard relacionado>) · [Logs](<consulta de log já filtrada>) · [Runbook](<item do runbook>)

{{#is_recovery}}✅ Recuperado após {{triggered_duration_sec}}s.{{/is_recovery}}

<os destinatários>
```

Recursos usados, e por quê: blocos condicionais por estado, para não enviar a mesma mensagem em alerta e em
recuperação; `{{value}}` e `{{threshold}}`, para dispensar a abertura da ferramenta; `{{<tag>.name}}`, para
nomear o grupo afetado (rota, pod, serviço, fila); `{{first_triggered_at}}` e `{{triggered_duration_sec}}`,
para duração; três links contextuais.

**O serviço da mensagem vem do mapa**, nos monitores de um serviço só. Nos que cobrem vários serviços com um
monitor agrupado por `service` — falhas no fluxo de ordens de serviço, mensagem na DLQ, relay do outbox
parado, falha na limpeza do cache — ele é `{{service.name}}`, resolvido pelo grupo que disparou.

**`{{env.name}}` não é usado.** Variável de tag só resolve quando a tag é dimensão de agrupamento do monitor,
e nenhum destes agrupa por `env`. O valor entra literal, vindo de `var.env`.

**Destinatários**: `var.alert_emails`, string separada por vírgula, renderizada em
`join(" ", [for e in split(",", var.alert_emails) : "@${trimspace(e)}"])`. O tipo é string e não lista porque
`TF_VAR_` de tipo complexo exige sintaxe HCL dentro de uma variável do provedor de código, que é frágil de
editar; e-mails não contêm vírgula, então a separação é inequívoca. **O valor vive fora do git**: o
repositório é público e endereço é dado pessoal.

---

## Disponibilidade externa `<contexto>` · rota pública indisponível

**Arquivo**: `terraform/synthetics.tf` · **Prioridade**: P1 · **Dashboard**: Visão Geral (grupo do serviço)

| Campo | Valor |
| --- | --- |
| Tipo | teste sintético `api` / `http`, um por serviço do mapa |
| Verificação | `GET {api_endpoint}/health/<contexto>` — o gateway reescreve a rota para a verificação de prontidão do serviço |
| Asserções | `statusCode is 200` **e** `responseTime lessThan 5000 ms` |
| Localidades | `var.synthetic_locations` — por padrão `aws:us-east-1`, `aws:sa-east-1`, `aws:eu-west-1` |
| Frequência | `var.synthetic_tick_every_seconds` — por padrão 300 s |
| Confirmação | `var.synthetic_min_location_failed` e `var.synthetic_min_failure_duration_seconds` — por padrão 2 localidades e 120 s |

**Por que existe.** A rota de saúde é excluída da instrumentação na entrada (L3): não há métrica, trace nem log
de sucesso para ela. A verificação externa responde se a rota pública de cada serviço está disponível pelo
caminho completo, e um teste por serviço diz **qual** caiu; ver
[ADR 0003](adr/0003-uptime-por-verificacao-externa.md).

**A localidade é de onde o Datadog executa a verificação, não onde a solução roda.** Toda a solução vive em
`us-east-1`, e é justamente por isso que há mais de uma: com uma só, qualquer problema de rede *daquela*
localidade viraria alerta de indisponibilidade. As três padrão são `us-east-1` (mesma região da solução, o
caminho mais curto), `sa-east-1` (onde o time e os usuários estão) e `eu-west-1` (o desempate).
`min_location_failed` é o quórum: duas precisam concordar antes de virar alerta.

Reduzir a duas localidades corta um terço do consumo de cota de execução e continua funcionando — mas passa a
exigir que **ambas** falhem, o que transforma uma localidade quebrada do lado do Datadog em silêncio. O
número é variável justamente para essa decisão ser uma linha de `.tfvars`. Com quatro testes, o consumo é de 4
testes × 3 localidades × 288 execuções por dia; se a cota apertar, a outra alavanca é
`synthetic_tick_every_seconds = 900`, uma execução a cada 15 minutos.

**Suspensão.** `status = var.environment_online ? "live" : "paused"`. Suspenso, o teste não executa, não consome
cota e não notifica — e a definição permanece versionada. Alternar `status` e não `count` preserva histórico e
identificador. O valor vem da variable `ENVIRONMENT_ONLINE`; o ritual está no [Runbook](runbook.md).

**O endereço muda a cada reprovisionamento**, e por isso vem de
`data.terraform_remote_state.gateway.outputs.api_endpoint`, nunca de uma variável editada à mão.

---

## Serviço `<contexto>` · Erros 5xx acima do limite

**Arquivo**: `terraform/monitors_service.tf` · **Prioridade**: P2 · **Dashboard**: o do serviço

```
sum(last_10m):count:http.server.request.duration{env:production,service:<serviço>,
  http.response.status_code:5*} by {http.route}.as_count() > 20
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| 5 | 20 | 10 min | `http.route` | 300 s |

**Contagem, não taxa.** Com tráfego esporádico, uma taxa dispara com "1 erro em 3 requisições". A taxa
permanece no dashboard, onde informa sem acordar ninguém. **Gatilho de migração para taxa**: volume sustentado
acima de 10 req/min.

**Agrupado por rota** para que uma rota quebrada não silencie o alerta de outra que quebre em seguida.
`new_group_delay` evita que uma rota recém-observada dispare antes de ter janela cheia.

**O filtro usa `http.response.status_code:5*`, não `error.type`**, porque `error.type` foi descartado do índice
pela configuração de tags — que é a alavanca de custo. Os dois são equivalentes: `error.type` só é preenchido
para 5xx e erro de transporte.

---

## Serviço `<contexto>` · Latência p95 acima do alvo

**Arquivo**: `terraform/monitors_service.tf` · **Prioridade**: P3 · **Dashboard**: o do serviço (grupo Latência)

```
percentile(last_15m):p95:http.server.request.duration{env:production,service:<serviço>} > 2
```

| Warning | Critical | Janela | Agrupamento |
| --- | --- | --- | --- |
| 1 s | 2 s | 15 min | **nenhum** |

**Sem agrupamento, deliberadamente**: agrupar por rota produziria tempestade de alertas numa degradação geral.
A quebra por rota está no dashboard, na tabela de rotas e no top 10 por p95.

**Os dois limiares são de percepção de usuário, e estão declarados como tais** — não são percentis observados.
O único dado medido, p95 de 23,5 ms no compose local (ADR 0005 do work-order), não representa produção. Os
quatro serviços usam os mesmos limiares até que a calibração mostre motivo para separá-los. O procedimento
está no [Runbook](runbook.md#calibração-de-limiares).

`percentile(...)` é o agregador temporal exigido por consulta de percentil. `require_full_window` fica
desligado porque este não é monitor de contagem.

**Depende de `datadog_metric_tag_configuration.http_server_request_duration`**, declarado como `depends_on`:
sem a configuração, a consulta responde `missing_aggregation` (L6).

---

## Ordens de Serviço · Falhas no processamento

**Arquivo**: `terraform/monitors_work_orders.tf` · **Prioridade**: P2 · **Dashboard**: Ordens de Serviço

```
sum(last_10m):count:http.server.request.duration{env:production AND http.response.status_code:5*
  AND ((service:oficina-mecanica-work-order-service AND http.route:/api/work-orders*)
    OR (service:oficina-mecanica-billing-service AND (http.route:/api/quotes* OR http.route:/api/work-orders*)))}
  by {service,http.route}.as_count() > 5
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| 2 | 5 | 10 min | `service`, `http.route` | 300 s |

**Duas famílias de rota, cada uma no serviço dono.** As ordens de serviço são do work-order; os orçamentos são
do billing, que também responde às rotas de orçamento aninhadas em `/api/work-orders` (como
`/api/work-orders/:id/quotes`). O agrupamento por serviço e rota faz o alerta dizer qual dos dois falhou, e o
monitor carrega a tag de serviço dos dois.

**Forma de consulta escolhida: métrica, não log.** O filtro por prefixo de rota foi verificado com dados reais
— `count:http.server.request.duration{http.route:/api/work-orders*} by {http.route}` devolve séries com
dados. O risco de que `/` e `:` no valor da tag inviabilizassem o glob **não se materializou**.

**Por que `AND` no lugar da vírgula.** O destino recusa `AND`/`OR` misturados com `,` no mesmo escopo
(`'AND' and 'OR' cannot be mixed with ','`), e `IN (…)` não aceita curinga. `AND` explícito na expressão
inteira é a única forma que compõe as duas famílias de rota com os seus serviços.

---

## Pod `<contexto>` · Memória próxima do limite

**Arquivo**: `terraform/monitors_kubernetes.tf` · **Prioridade**: P2 · **Dashboard**: Kubernetes

```
avg(last_10m):(avg:kubernetes.memory.working_set{kube_namespace:<contexto>,kube_deployment:<contexto>-service} by {pod_name}
  / avg:kubernetes.memory.limits{kube_namespace:<contexto>,kube_deployment:<contexto>-service} by {pod_name}) * 100 > 90
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| 80 % | 90 % | 10 min | `pod_name` | 300 s |

`working_set` e não `usage`, porque `working_set` é o que o encerramento por falta de memória observa.

---

## Pod `<contexto>` · Reinícios de contêiner

**Arquivo**: `terraform/monitors_kubernetes.tf` · **Prioridade**: P3 · **Dashboard**: Kubernetes

```
max(last_10m):diff(max:kubernetes.containers.restarts{kube_namespace:<contexto>,kube_deployment:<contexto>-service} by {pod_name}) > 0
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| — | > 0 | 10 min | `pod_name` | **600 s** |

`kubernetes.containers.restarts` é um contador cumulativo: interessa a **variação** na janela, não o valor
absoluto, que só cresce. `diff()` devolve o incremento entre pontos consecutivos, e `max(last_10m)` dele
responde "houve reinício na janela?" — verificado contra um pod em `CrashLoopBackOff`, que devolve valor
positivo enquanto o pod saudável devolve `0`.

**Não use a família `change()` aqui.** Ela não dispara neste cenário, mesmo com a variação do contador sendo
positiva.

**`new_group_delay` de 600 s** é maior que o dos demais porque todo provisionamento cria pods novos, e um pod
recém-criado tem contador partindo do zero. Sem a folga, cada subida do laboratório geraria alerta.

**O `{{value}}` deste alerta não é uma contagem de reinícios.** `diff()` devolve o incremento entre pontos
consecutivos do contador, suavizado pelo rollup do destino: um pod que reiniciou oito vezes produz um valor
como `0.1`. A informação acionável está na **linha do sintoma** — `Contêiner reiniciou — pod <nome>` — e por
isso a unidade diz *de aumento no contador de reinícios*, não *reinícios*.

---

## Lambda `<função>` · Erros de execução

**Arquivo**: `terraform/monitors_lambda.tf` · **Prioridade**: P2 · **Dashboard**: Visão Geral (grupo da Lambda)

```
sum(last_10m):sum:aws.lambda.enhanced.errors{functionname:<nome da função>}.as_count() > 0
```

| Warning | Critical | Janela | Agrupamento | `require_full_window` |
| --- | --- | --- | --- | --- |
| — | > 0 | 10 min | nenhum | **`false`** |

Um monitor por função do mapa de Lambdas: `lbd-oficina-mecanica-customer-auth` e
`lbd-oficina-mecanica-notification`.

**Escopado por `functionname` e não por `env`.** O nome da função já a identifica sem ambiguidade; a função
emite `env:production`.

**Alerta em qualquer erro** porque erro de plataforma é a execução que falhou — exceção não tratada, prazo
esgotado, falta de memória — e não uma resposta de negócio. A customer-auth devolve 401 como resposta normal
de credencial inválida, e a notification devolve à fila a mensagem que não conseguiu enviar e registra
`notification.failed`, contado pelo monitor de falha de envio de e-mail. Monitores separados para expiração de
prazo (`timeouts`) e falta de memória (`out_of_memory`) seriam redundantes — os dois também incrementam
`errors`.

**O estado normal deste monitor é `No Data`, não `OK`.** `aws.lambda.enhanced.errors` não existe na conta
enquanto nenhuma falha ocorre (L14): a extensão só emite a métrica no evento. Com `notify_no_data = false`
isso não notifica, que é exatamente o desejado num ambiente que passa a maior parte do tempo desligado. É
também por isso que `require_full_window` fica desligado aqui: numa métrica esparsa ele atrasaria a avaliação
justamente quando a série enfim aparecesse.

---

## Lambda notification · Falha de envio de e-mail

**Arquivo**: `terraform/monitors_integrations.tf` · **Prioridade**: P4 · **Dashboard**: Visão Geral

```
logs("service:oficina-mecanica-lambda-notification env:production @oficina.event.name:notification.failed")
  .index("*").rollup("count").by("@oficina.notification.failure.reason,@oficina.notification.purpose").last("15m") > 5
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| 2 | 5 | 15 min | `@oficina.notification.failure.reason`, `@oficina.notification.purpose` | 300 s |

Os serviços pedem e-mails pela fila `notification.fifo`, e a Lambda notification os envia por SMTP. Cada
tentativa que falha registra `notification.failed`.

**Agrupado por motivo e por propósito** porque a ação muda com o motivo e o impacto muda com o propósito.
`smtp_error` é o servidor de e-mail recusando ou fora do ar; `invalid_message` é uma mensagem da fila que a
Lambda não consegue ler. O propósito, informado pelo serviço que pediu o e-mail, diz que tipo de e-mail falhou;
a Lambda registra `unspecified` quando ele falta, então nenhuma falha fica fora dos grupos.

**Monitor de log porque não existe métrica equivalente**, e a cardinalidade — motivo × propósito — não
justificaria criar uma.

`notification.failed` só é emitido quando ocorre uma falha de envio (L15). Sem esse evento no intervalo,
não há contagem de falhas para comparar ao limiar; ausência de ocorrência não comprova entrega de e-mail.

---

## Serviço `<contexto>` · Health check degradado

**Arquivo**: `terraform/monitors_integrations.tf` · **Prioridade**: P3 · **Dashboard**: o do serviço

```
logs("service:<serviço> env:production @oficina.event.name:health.degraded")
  .index("*").rollup("count").by("@oficina.dependency.name,@oficina.health.failure.category").last("10m") > 0
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| — | > 0 | 10 min | `@oficina.dependency.name`, `@oficina.health.failure.category` | 300 s |

O evento é emitido pela própria verificação de prontidão do serviço quando uma dependência responde fora do
esperado. É o único sinal que nomeia **qual** dependência falhou e **como** — a rota de saúde é excluída da
instrumentação na entrada (L3), então não há métrica nem trace dela. Hoje a verificação cobre só o banco.

`health.degraded` só é emitido quando a verificação detecta degradação (L15). Um intervalo sem esse evento
não contém amostras de falha da dependência.

Toda consulta de log escopa por `service` **por inclusão**: o índice também recebe componentes de plataforma,
como `metrics-server`, cujos logs não devem ser interpretados como defeitos da aplicação (L7).

---

## Mensageria · Mensagem na DLQ

**Arquivo**: `terraform/monitors_messaging.tf` · **Prioridade**: P2 · **Dashboard**: Mensageria

```
logs("<4 serviços> @oficina.event.name:messaging.message.dead_lettered")
  .index("*").rollup("count").by("service,@messaging.destination.name,@oficina.messaging.message.type").last("10m") > 0
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| — | > 0 | 10 min | `service`, `@messaging.destination.name`, `@oficina.messaging.message.type` | 300 s |

`<4 serviços>` é `env:production AND (service:… OR …)` com os quatro serviços (`local.services_scope`).

Uma mensagem que o consumidor não consegue processar em 5 tentativas vai para a DLQ (dead-letter queue, a fila
das mensagens desistidas) da sua fila. Pouco antes, o consumidor registra `messaging.message.dead_lettered`,
com a fila e o tipo da mensagem. **Cada ocorrência deixa uma ordem de serviço parada** até a mensagem voltar à
fila, por isso o limiar é zero. O alerta nomeia o serviço consumidor, a fila e o tipo.

**Por evento de log, e não pela profundidade da DLQ**, porque a profundidade é métrica do SQS, que exige a
integração AWS do Datadog, indisponível no laboratório (L2). Com a integração, a profundidade da DLQ seria o
sinal mais direto.

**Sem tag de serviço**: é um monitor só para os quatro serviços, e aparece em "Monitores da solução" na Visão
Geral ([Convenções](conventions.md#tags-dos-recursos-criados)). O identity não consome fila e nunca forma
grupo aqui.

---

## Mensageria · Relay do outbox parado

**Arquivo**: `terraform/monitors_messaging.tf` · **Prioridade**: P2 · **Dashboard**: Mensageria

```
logs("<4 serviços> @oficina.event.name:messaging.outbox.publish_failed")
  .index("*").rollup("count").by("service").last("5m") > 10
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| — | > 10 | 5 min | `service` | 300 s |

Cada serviço grava a mensagem que vai publicar numa tabela `outbox`, na mesma transação da mudança de negócio,
e um laço do serviço (o relay) a publica no tópico SNS. Para não furar a ordem, o relay para no primeiro erro
do lote e tenta de novo no ciclo seguinte, registrando `messaging.outbox.publish_failed` a cada ciclo com
falha. Uma falha persistente segura **todas** as mensagens do serviço.

**Limiar provisório de 10 em 5 minutos.** O relay tenta a cada meio segundo, com até 2 segundos de prazo por
publicação: uma falha persistente gera mais de 120 eventos em 5 minutos, e uma falha isolada, publicada no
ciclo seguinte, gera 1. O limiar fica longe dos dois. Calibrar pelo [Runbook](runbook.md#calibração-de-limiares).

**Sem tag de serviço**, pelo mesmo motivo do monitor de DLQ.

---

## Pagamentos · Webhook com assinatura inválida

**Arquivo**: `terraform/monitors_payments.tf` · **Prioridade**: P2 · **Dashboard**: Pagamentos

```
logs("service:oficina-mecanica-billing-service env:production @oficina.event.name:payment.webhook.invalid_signature")
  .index("*").rollup("count").last("15m") > 3
```

| Warning | Critical | Janela | Agrupamento |
| --- | --- | --- | --- |
| — | > 3 | 15 min | nenhum |

O Mercado Pago avisa o billing de cada mudança de cobrança por uma notificação HTTP (webhook) assinada com uma
chave secreta. O billing recusa a notificação cuja assinatura não confere e registra
`payment.webhook.invalid_signature`.

**Limiar provisório de 3 em 15 minutos.** Uma chave errada no billing recusa todas as notificações, e o Mercado
Pago as reenvia: a contagem passa do limiar em minutos, e nenhuma cobrança é atualizada. Uma sondagem isolada
de quem não conhece a chave fica abaixo.

**Sem agrupamento**: o evento é de um único serviço e de um único provedor.

---

## Sagas · Compensações da aprovação de orçamento

**Arquivo**: `terraform/monitors_sagas.tf` · **Prioridade**: P3 · **Dashboard**: Sagas

```
sum(last_1h):sum:oficina.saga.finished{env:production,service:oficina-mecanica-work-order-service,
  oficina.saga.outcome:compensated,oficina.saga.type:QUOTE_APPROVAL}.as_count() > 1
```

| Warning | Critical | Janela | Agrupamento | `require_full_window` |
| --- | --- | --- | --- | --- |
| — | > 1 | 1 h | nenhum | **`false`** |

A aprovação de um orçamento é uma Saga (`QUOTE_APPROVAL`) que atravessa billing, inventory e work-order. Quando
um passo falha — tipicamente a reserva de peças, por falta de estoque —, os passos anteriores são desfeitos e
a Saga termina `compensated`.

**Contagem absoluta, e não taxa.** Com o volume deste ambiente, uma taxa de compensação dispara com uma única
amostra. Uma compensação isolada é desfecho de negócio; duas na janela de uma hora pedem olhar o estoque ou o
serviço que recusou o passo. O limiar é provisório. A taxa fica no dashboard de Sagas.

**Só `QUOTE_APPROVAL`.** A Saga de pagamento (`PAYMENT`) termina compensada quando a cobrança é recusada,
expira ou é cancelada — desfechos normais do pagamento, não defeito. Dois cartões recusados na janela
disparariam o alerta. As compensações de `PAYMENT` ficam no dashboard de Sagas, e as cobranças por status no de
Pagamentos.

`require_full_window` fica desligado pelo mesmo motivo do monitor das Lambdas: a série só existe depois da
primeira Saga finalizada.

---

## Cache · Falha na limpeza do cache

**Arquivo**: `terraform/monitors_cache.tf` · **Prioridade**: P3 · **Dashboard**: Visão Geral

```
logs("<4 serviços> @oficina.event.name:cache.invalidation_failed")
  .index("*").rollup("count").by("service").last("10m") > 0
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| — | > 0 | 10 min | `service` | 300 s |

Cada serviço guarda leituras por id no próprio cache (Valkey, compatível com Redis) e apaga a chave afetada
depois de confirmar uma escrita. Quando a exclusão falha, o serviço registra `cache.invalidation_failed`, e a
leitura seguinte devolve o valor antigo até a chave expirar, em até 12 horas. **Qualquer ocorrência é um dado
errado servido ao usuário**, por isso o limiar é zero.

**Sem tag de serviço**, pelo mesmo motivo do monitor de DLQ.

---

## Sobreposições assumidas

Alguns monitores observam o mesmo incidente por ângulos diferentes. Cada sobreposição abaixo é deliberada.

| Monitores | O que se sobrepõe | Por que os dois ficam |
| --- | --- | --- |
| Erros 5xx do serviço × Falhas no fluxo de ordens de serviço | Uma indisponibilidade total do work-order ou do billing dispara os dois | São leituras distintas — "o serviço está falhando" e "o fluxo de negócio está quebrado" — para públicos distintos. Um monitor composto seria cerimônia desproporcional; um só agrupado por rota perderia a nomeação do impacto de negócio |
| Mensagem na DLQ × Falha de envio de e-mail | A fila `notification.fifo`, da Lambda notification, também tem DLQ | Quem a vigia é o monitor de e-mail, não o de DLQ: a Lambda registra `notification.failed` com `oficina.notification.outcome: dead_lettered`, e não `messaging.message.dead_lettered`. Um e-mail que chega à DLQ soma 5 falhas em cerca de 2,5 minutos (visibilidade de 30 s e 5 recebimentos) e dispara o `warning` do monitor de e-mail (5 > 2), não o `critical` (5 > 5 é falso). Um e-mail perdido não para uma ordem de serviço, ao contrário de uma mensagem entre serviços |
| Relay do outbox parado × Mensagem na DLQ | Os dois explicam uma Saga parada | Não disparam pela mesma mensagem: o outbox é a mensagem que não saiu do produtor, a DLQ é a que saiu e o consumidor desistiu. Ambos apontam para o dashboard de Mensageria, onde as duas pontas aparecem juntas |
| Webhook com assinatura inválida (log) × webhooks por resultado (métrica, no dashboard de Pagamentos) | O billing registra a mesma recusa como evento de log e como `oficina.payment.webhook.received{outcome:invalid_signature}` | O monitor usa o log porque a amostra de linhas no e-mail traz o motivo da recusa (`@oficina.mp.signature.failure_reason`); o dashboard usa a métrica, que mostra válidos e inválidos lado a lado. As duas contagens podem diferir por segundos de atraso de ingestão |
| Health check degradado × Erros 5xx e Latência p95 do mesmo serviço | Banco degradado costuma disparar os três | O health check nomeia a dependência e a categoria da falha, que os outros dois não nomeiam: é por ele que a investigação começa |

---

## Alertas recusados

| Recusado | Motivo |
| --- | --- |
| **Coleta interrompida** | Seu disparo seria garantido ao final de toda sessão do laboratório. **Gatilho para reintroduzir**: o ambiente passar a ser permanente |
| **CPU alta** | Com autoescalonamento mirando 70 % de CPU, "CPU alta" é o mecanismo funcionando. O sinal acionável seria estrangulamento sustentado, que fica no dashboard e só vira monitor se a latência provar correlação |
| **Nenhuma OS criada em 24 h** | Dispararia todo dia num ambiente efêmero |
| **Permanência média por status acima de X** | Não existe acordo de negócio, e inventar um limiar produz alerta permanentemente vermelho ou permanentemente verde |
| **Latência de banco em monitor próprio** | Sem latência alta no serviço não é incidente; com ela, o monitor de latência já disparou e o dashboard mostra a causa |
| **Descarte de span pelo canal `diag` do OTel** | Descarte por fila cheia é comportamento **declarado como aceito** no ADR 0005 do work-order. Alertar contrariaria a decisão de origem |
| **Qualquer monitor sobre `kubernetes_state.*`** | Não existe (L1) |
| **Timeouts e falta de memória das Lambdas em monitores próprios** | Redundantes com o monitor de erros de execução |
| **Profundidade de fila e idade da mensagem mais antiga** | Métricas do SQS, que exigem a integração AWS do Datadog, indisponível no laboratório (L2). A DLQ é vigiada pelo evento que o consumidor registra |
| **Cobrança expirada ou recusada** | Desfecho normal do pagamento: o cliente não pagou no prazo ou o cartão foi recusado. Fica no dashboard de Pagamentos |
| **Compensações da Saga de pagamento** | Consequência das mesmas cobranças recusadas, expiradas ou canceladas. Ficam no dashboard de Sagas |
| **Taxa de compensação de Saga** | Com este volume, dispara com uma amostra. O monitor usa contagem absoluta, e a taxa fica no dashboard de Sagas |

---

## Calibração de limiar

O procedimento operacional completo está no [Runbook](runbook.md#calibração-de-limiares). Em resumo:

1. **Latência** — após uma semana com tráfego representativo, ler p95 e p99 reais no dashboard de cada serviço
   e ajustar os limiares para **2×** e **4×** o p95 observado, em Pull Request próprio cuja descrição cite os
   valores medidos.
2. **Contagem** — erros 5xx, falhas no fluxo de ordens de serviço, falha de envio de e-mail e os limiares
   provisórios (relay do outbox, webhook com assinatura inválida, compensações): comparar os limiares com o
   volume real observado na semana. Se algum disparou por falso positivo, subir o limiar; se um incidente real
   passou sem alerta, descer.
3. **Todo ajuste é Pull Request**, com o valor observado na descrição. Um limiar sem justificativa registrada
   é um número inventado, e a próxima pessoa não saberá se pode mexer.

Os limiares são variáveis em `terraform/variables.tf`, com valores em `terraform/terraform.tfvars`: a
calibração é uma linha de `.tfvars`, não uma edição de consulta. A lista completa está em
[Infraestrutura](terraform.md#variáveis).

---

## Como acrescentar um monitor

1. Confirme que **cada nome de métrica, tag e faceta existe na conta**, com uma consulta que devolve dados, ou,
   para um evento que só aparece na falha, no catálogo do repositório que o emite
   ([Convenções](conventions.md#sinais-da-solução-distribuída)).
2. Valide a consulta de alerta isoladamente antes de escrever HCL:
   `POST /api/v1/monitor/validate` com `{name, type, query, message, options.thresholds}`.
3. Declare no arquivo da família (`monitors_<família>.tf`), nomeando como
   `[Oficina Mecânica] <Componente> · <Sintoma>` — ver [Convenções](conventions.md). Se ele se repete por
   serviço, use `for_each = local.services`.
4. Aplique a configuração comum do topo deste documento e componha a mensagem com `local.monitor_message`.
5. Escreva o item no [Runbook](runbook.md) e aponte `runbook_url` para a âncora dele.
6. Acrescente o identificador ao output `monitor_ids` em `terraform/outputs.tf`.
7. Documente aqui: consulta, limiares, janela, agrupamento, prioridade, mensagem e dashboard relacionado.
8. Pergunte-se, na revisão: **o que a pessoa faz ao receber este e-mail às 3 da manhã?** Se a resposta for
   "olha e volta a dormir", o alerta é um widget de dashboard, não um monitor.
