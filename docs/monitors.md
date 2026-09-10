# Monitores

Nove monitores, distribuídos em cinco arquivos `terraform/monitors_*.tf` mais o teste sintético em
`terraform/synthetics.tf`. Este documento é a fonte única das consultas de alerta.

Os nomes dos sinais e o motivo de cada ausência estão em [Observabilidade](observability.md), citados por
sigla. As consultas dos widgets estão em [Dashboards](dashboards.md) e não se repetem aqui.

---

## Configuração comum

Aplicada aos nove, e cada item tem razão:

| Opção | Valor | Por quê |
| --- | --- | --- |
| `notify_no_data` | **`false`** em todos | O laboratório é ligado sob demanda e destruído ao final (L10). Notificar por ausência de dado dispararia nove alertas ao fim de toda sessão |
| `renotify_interval` | `0` | Não há plantão. Repetir o alerta a cada N minutos treina o time a silenciar a caixa de entrada |
| `notify_audit` | `false` | Mudança de definição do monitor é vista no Pull Request, não por e-mail |
| `include_tags` | `true` | O e-mail carrega as tags do grupo afetado |
| `require_full_window` | `true` **nos monitores de contagem** | Contagem parcial de janela produz falso negativo. **Exceção: erros da Lambda**, cuja métrica só passa a existir na primeira falha (L14) |
| `escalation_message` | não usado | Não há plantão para escalar |
| `notify_by` | **não usado** | O destino recusa uma lista que cubra *todos* os agrupamentos da consulta — `The notify_by list may not include all of the query's group keys` — e os monitores agrupados aqui têm uma única chave de agrupamento. O comportamento pretendido, uma notificação por rota ou por pod afetado, **já é o padrão** de um monitor agrupado |
| `tags` | `project:oficina-mecanica`, `managed-by:terraform`, `env:…`, `service:…` | Ver [Convenções](conventions.md) |

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

[Dashboard](<dashboard relacionado>) · [Logs](<consulta de log já filtrada>)

{{#is_recovery}}✅ Recuperado após {{triggered_duration_sec}}s.{{/is_recovery}}

<os quatro destinatários>
```

Recursos usados, e por quê: blocos condicionais por estado, para não enviar a mesma mensagem em alerta e em
recuperação; `{{value}}` e `{{threshold}}`, para dispensar a abertura da ferramenta; `{{<tag>.name}}`, para
nomear o grupo afetado; `{{first_triggered_at}}` e `{{triggered_duration_sec}}`, para duração; dois links
contextuais.

**`{{env.name}}` não é usado.** Variável de tag só resolve quando a tag é dimensão de agrupamento do monitor,
e nenhum destes agrupa por `env`. O valor entra literal, vindo de `var.env`.

**Destinatários**: `var.alert_emails`, string separada por vírgula, renderizada em
`join(" ", [for e in split(",", var.alert_emails) : "@${trimspace(e)}"])`. O tipo é string e não lista porque
`TF_VAR_` de tipo complexo exige sintaxe HCL dentro de uma variável do provedor de código, que é frágil de
editar; e-mails não contêm vírgula, então a separação é inequívoca. **O valor vive fora do git**: o
repositório é público e endereço é dado pessoal.

---

## Disponibilidade externa · rota pública indisponível

**Arquivo**: `terraform/synthetics.tf` · **Prioridade**: P1 · **Dashboard**: Visão Geral (grupo Disponibilidade)

| Campo | Valor |
| --- | --- |
| Tipo | teste sintético `api` / `http` |
| Verificação | `GET {api_endpoint}/api/health/ready` |
| Asserções | `statusCode is 200` **e** `responseTime lessThan 5000 ms` |
| Localidades | `var.synthetic_locations` — por padrão `aws:us-east-1`, `aws:sa-east-1`, `aws:eu-west-1` |
| Frequência | `var.synthetic_tick_every_seconds` — por padrão 300 s |
| Confirmação | `var.synthetic_min_location_failed` e `var.synthetic_min_failure_duration_seconds` — por padrão 2 localidades e 120 s |

**Por que existe.** A rota de saúde é excluída da instrumentação na entrada (L3): não há métrica, trace nem log
de sucesso para ela. Verificação externa é a única forma de responder "a rota pública está de pé?", e é a
dívida que o ADR 0005 da API declarou e não quitou — ver [ADR 0003](adr/0003-uptime-por-verificacao-externa.md).

**A localidade é de onde o Datadog executa a verificação, não onde a API roda.** Toda a solução vive em
`us-east-1`, e é justamente por isso que há mais de uma: com uma só, qualquer problema de rede *daquela*
localidade viraria alerta de indisponibilidade. As três padrão são `us-east-1` (mesma região da API, o caminho
mais curto), `sa-east-1` (onde o time e os usuários estão) e `eu-west-1` (o desempate). `min_location_failed`
é o quórum: duas precisam concordar antes de virar alerta.

Reduzir a duas localidades corta um terço do consumo de cota de execução e continua funcionando — mas passa a
exigir que **ambas** falhem, o que transforma uma localidade quebrada do lado do Datadog em silêncio. O
número é variável justamente para essa decisão ser uma linha de `.tfvars`.

**Suspensão.** `status = var.environment_online ? "live" : "paused"`. Suspenso, o teste não executa, não consome
cota e não notifica — e a definição permanece versionada. Alternar `status` e não `count` preserva histórico e
identificador. O valor vem da variable `ENVIRONMENT_ONLINE`; o ritual está no [Runbook](runbook.md).

**O endereço muda a cada reprovisionamento**, e por isso vem de
`data.terraform_remote_state.gateway.outputs.api_endpoint`, nunca de uma variável editada à mão.

---

## API · Erros 5xx acima do limite

**Arquivo**: `terraform/monitors_api.tf` · **Prioridade**: P2 · **Dashboard**: API

```
sum(last_10m):count:http.server.request.duration{env:production,service:oficina-mecanica-api,
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

## API · Latência p95 acima do alvo

**Arquivo**: `terraform/monitors_api.tf` · **Prioridade**: P3 · **Dashboard**: API (grupo Latência)

```
percentile(last_15m):p95:http.server.request.duration{env:production,service:oficina-mecanica-api} > 2
```

| Warning | Critical | Janela | Agrupamento |
| --- | --- | --- | --- |
| 1 s | 2 s | 15 min | **nenhum** |

**Sem agrupamento, deliberadamente**: agrupar por rota produziria tempestade de alertas numa degradação geral.
A quebra por rota está no dashboard, na tabela de rotas e no top 10 por p95.

**Os dois limiares são de percepção de usuário, e estão declarados como tais** — não são percentis observados.
O único dado medido, p95 de 23,5 ms no compose local (ADR 0005 da API), não representa produção. O
procedimento de calibração está no [Runbook](runbook.md).

`percentile(...)` é o agregador temporal exigido por consulta de percentil. `require_full_window` fica
desligado porque este não é monitor de contagem.

**Depende de `datadog_metric_tag_configuration.http_server_request_duration`**, declarado como `depends_on`:
sem a configuração, a consulta responde `missing_aggregation` (L6).

---

## Ordens de Serviço · Falhas no processamento

**Arquivo**: `terraform/monitors_work_orders.tf` · **Prioridade**: P2 · **Dashboard**: Ordens de Serviço

```
sum(last_10m):count:http.server.request.duration{env:production AND service:oficina-mecanica-api
  AND http.response.status_code:5*
  AND (http.route:/api/work-orders* OR http.route:/api/quotes*)} by {http.route}.as_count() > 5
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| 2 | 5 | 10 min | `http.route` | 300 s |

**Forma de consulta escolhida: métrica, não log.** O filtro por prefixo de rota foi verificado com dados reais
— `count:http.server.request.duration{http.route:/api/work-orders*} by {http.route}` devolve três séries com
dados. O risco de que `/` e `:` no valor da tag inviabilizassem o glob **não se materializou**, e o fallback de
monitor de log sobre a linha de access log fica registrado e não adotado.

**Por que `AND` no lugar da vírgula.** O destino recusa `AND`/`OR` misturados com `,` no mesmo escopo
(`'AND' and 'OR' cannot be mixed with ','`), e `IN (…)` não aceita curinga. `AND` explícito na expressão
inteira é a única forma que compõe o filtro de duas famílias de rota.

### A redundância com o monitor de erros 5xx é assumida

Este monitor e o de erros 5xx se sobrepõem numa indisponibilidade total, **e isso é aceito**. São leituras distintas — "a API está
falhando" e "o fluxo de negócio está quebrado" — para públicos distintos. As alternativas foram avaliadas e
recusadas: um monitor composto seria cerimônia desproporcional; um único monitor agrupado por rota perderia a
nomeação do impacto de negócio que o requisito pede.

---

## Pod · Memória próxima do limite

**Arquivo**: `terraform/monitors_kubernetes.tf` · **Prioridade**: P2 · **Dashboard**: Kubernetes

```
avg(last_10m):(avg:kubernetes.memory.working_set{kube_deployment:oficina-api} by {pod_name}
  / avg:kubernetes.memory.limits{kube_deployment:oficina-api} by {pod_name}) * 100 > 90
```

| Warning | Critical | Janela | Agrupamento | `new_group_delay` |
| --- | --- | --- | --- | --- |
| 80 % | 90 % | 10 min | `pod_name` | 300 s |

`working_set` e não `usage`, porque `working_set` é o que o encerramento por falta de memória observa.

---

## Pod · Reinícios de contêiner

**Arquivo**: `terraform/monitors_kubernetes.tf` · **Prioridade**: P3 · **Dashboard**: Kubernetes

```
max(last_10m):diff(max:kubernetes.containers.restarts{kube_deployment:oficina-api} by {pod_name}) > 0
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

## Lambda customer-auth · Erros de execução

**Arquivo**: `terraform/monitors_lambda.tf` · **Prioridade**: P2 · **Dashboard**: Visão Geral (grupo Lambda)

```
sum(last_10m):sum:aws.lambda.enhanced.errors{functionname:lbd-oficina-mecanica-customer-auth}.as_count() > 0
```

| Warning | Critical | Janela | Agrupamento | `require_full_window` |
| --- | --- | --- | --- | --- |
| — | > 0 | 10 min | nenhum | **`false`** |

**Escopado por `functionname` e não por `env`.** Até a unificação de `DD_ENV`, a função emitia
`env:prod-simulated` enquanto a API emitia `env:production` (L8). O `functionname` funciona antes e depois
dessa correção — foi o que permitiu que o monitor não dependesse dela. **A unificação já foi integrada** e a
função emite `env:production`, mas o escopo continua por `functionname`: é o identificador estável da função,
e não há segunda função a distinguir.

**Alerta em qualquer erro** porque a função devolve 401 como resposta normal de credencial inválida: erro de
plataforma é sempre defeito. Monitores separados para expiração de prazo (`timeouts`) e falta de memória
(`out_of_memory`) seriam redundantes — os dois também incrementam `errors`.

**O estado normal deste monitor é `No Data`, não `OK`.** `aws.lambda.enhanced.errors` não existe na conta
enquanto nenhuma falha ocorre (L14): a extensão só emite a métrica no evento. Com `notify_no_data = false`
isso não notifica, que é exatamente o desejado num ambiente que passa a maior parte do tempo desligado. É
também por isso que `require_full_window` fica desligado aqui: numa métrica esparsa ele atrasaria a avaliação
justamente quando a série enfim aparecesse.

---

## Integrações · Falha de envio de e-mail

**Arquivo**: `terraform/monitors_integrations.tf` · **Prioridade**: P4 · **Dashboard**: API

```
logs("service:oficina-mecanica-api env:production @oficina.event.name:mail.send.failed")
  .index("*").rollup("count").by("@oficina.mail.error.category").last("15m") > 5
```

| Warning | Critical | Janela | Agrupamento |
| --- | --- | --- | --- |
| 2 | 5 | 15 min | `@oficina.mail.error.category` |

**Agrupado por categoria de erro** porque a ação muda com ela: credencial recusada é problema de configuração,
tempo esgotado é problema de rede, endereço inválido é problema de dado.

**Monitor de log porque não existe métrica equivalente**, e a cardinalidade — operação × categoria — não
justificaria criar uma.

⚠️ **`mail.send.failed` tem zero ocorrências em 30 dias de índice** (L15). O monitor é válido — contagem vazia
é zero, que é o estado saudável — mas **não pode ser dado por verificado de ponta a ponta sem provocar o evento
na origem**.

---

## Dependência · Health check degradado

**Arquivo**: `terraform/monitors_integrations.tf` · **Prioridade**: P3 · **Dashboard**: API

```
logs("service:oficina-mecanica-api env:production @oficina.event.name:health.degraded")
  .index("*").rollup("count").by("@oficina.health.failure.category").last("10m") > 0
```

| Warning | Critical | Janela | Agrupamento |
| --- | --- | --- | --- |
| — | > 0 | 10 min | `@oficina.health.failure.category` |

O evento é emitido pela própria verificação de saúde interna quando uma dependência responde fora do esperado.
É o único sinal que nomeia **qual** dependência falhou — a rota de saúde é excluída da instrumentação na
entrada (L3), então não há métrica nem trace dela.

⚠️ Mesmo aviso do monitor de e-mail: **`health.degraded` nunca foi observado** (L15).

Toda consulta de log escopa por `service` **por inclusão**: o índice recebe o cluster inteiro, ~35 % dele é
ruído de plataforma e `klog` escreve em stderr, então qualquer consulta de erro sem escopo traria `kube-proxy`
e `metrics-server` como se fossem defeito da aplicação (L7).

---

## Alertas recusados

| Recusado | Motivo |
| --- | --- |
| **Coleta interrompida** | Seu disparo seria garantido ao final de toda sessão do laboratório. **Gatilho para reintroduzir**: o ambiente passar a ser permanente |
| **CPU alta** | Com autoescalonamento mirando 70 % de CPU, "CPU alta" é o mecanismo funcionando. O sinal acionável seria estrangulamento sustentado, que fica no dashboard e só vira monitor se a latência da API provar correlação |
| **Nenhuma OS criada em 24 h** | Dispararia todo dia num ambiente efêmero |
| **Permanência média por status acima de X** | Não existe acordo de negócio, e inventar um limiar produz alerta permanentemente vermelho ou permanentemente verde |
| **Latência de banco em monitor próprio** | Sem latência de API alta não é incidente; com ela, o monitor de latência já disparou e o dashboard mostra a causa |
| **Descarte de span pelo canal `diag` do OTel** | Descarte por fila cheia é comportamento **declarado como aceito** no ADR 0005 da API. Alertar contrariaria a decisão de origem |
| **Qualquer monitor sobre `kubernetes_state.*`** | Não existe (L1) |
| **Timeouts e falta de memória da Lambda em monitores próprios** | Redundantes com o monitor de erros de execução da Lambda |

---

## Calibração de limiar

O procedimento operacional completo está no [Runbook](runbook.md). Em resumo:

1. **Latência** — após uma semana com tráfego representativo, ler p95 e p99 reais no dashboard de API e
   ajustar os limiares para **2×** e **4×** o p95 observado, em Pull Request próprio cuja descrição cite os
   valores medidos.
2. **Contagem** — erros 5xx, falhas no fluxo de ordens de serviço e falha de envio de e-mail: comparar os limiares com o volume real de 5xx observado na semana. Se algum
   disparou por falso positivo, subir o limiar; se um incidente real passou sem alerta, descer.
3. **Todo ajuste é Pull Request**, com o valor observado na descrição. Um limiar sem justificativa registrada
   é um número inventado, e a próxima pessoa não saberá se pode mexer.

Os limiares são variáveis em `terraform/variables.tf`, com valores em `terraform/terraform.tfvars`: a
calibração é uma linha de `.tfvars`, não uma edição de consulta.

---

## Como acrescentar um monitor

1. Confirme que **cada nome de métrica, tag e faceta existe na conta**, com uma consulta que devolve dados.
2. Valide a consulta de alerta isoladamente antes de escrever HCL:
   `POST /api/v1/monitor/validate` com `{name, type, query, message, options.thresholds}`.
3. Declare no arquivo da família (`monitors_<família>.tf`), nomeando como
   `[Oficina Mecânica] <Componente> · <Sintoma>` — ver [Convenções](conventions.md).
4. Aplique a configuração comum do topo deste documento e componha a mensagem com `local.monitor_message`.
5. Acrescente o identificador ao output `monitor_ids` em `terraform/outputs.tf`.
6. Documente aqui: consulta, limiares, janela, agrupamento, prioridade, mensagem e dashboard relacionado.
7. Pergunte-se, na revisão: **o que a pessoa faz ao receber este e-mail às 3 da manhã?** Se a resposta for
   "olha e volta a dormir", o alerta é um widget de dashboard, não um monitor.
