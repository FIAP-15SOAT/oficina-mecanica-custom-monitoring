# Observabilidade

Documento âncora deste repositório. Inventaria **o que a solução realmente emite** e, com o mesmo cuidado,
**o que ela não emite** — porque metade das perguntas de revisão sobre um dashboard é "por que isto não está
aqui?", e a resposta precisa estar escrita em um só lugar.

Todo nome citado abaixo foi confirmado contra a conta em `us5` por consulta à API, não deduzido do código.
O registro bruto da descoberta está no histórico da mudança OpenSpec `custom-monitoring-datadog`.

---

## 1. Como o sinal chega ao destino

| Origem | Caminho | O que chega |
| --- | --- | --- |
| API (NestJS, pods no EKS) | SDK OpenTelemetry → exportador OTLP → Datadog Agent 7.60 (DaemonSet) | métricas, traces e logs |
| Lambda `customer-auth` | Extensão Datadog (camada Lambda) | métricas *enhanced* e logs; **sem traces** |
| Cluster Kubernetes | Datadog Agent, coleta do *kubelet* | métricas de contêiner, pod e nó |
| Rota pública `/api/health/ready` | Teste sintético deste repositório | disponibilidade externa |

Este repositório não coleta nada. Ele **consome** o que já chega, e é dono de tudo que lê: dashboards,
monitores, teste sintético e configuração de métrica.

---

## 2. Sinais disponíveis

### 2.1 Métricas de negócio

Emitidas pela API a partir de `business-metric.catalog.ts`. Temporalidade **delta**, intervalo de 60 s.

| Métrica | Tipo | Unidade | Tags | Observação |
| --- | --- | --- | --- | --- |
| `oficina.work_order.created` | contador | `{work_order}` | `env`, `service`, `version` | conta nascimento de OS |
| `oficina.work_order.status.duration` | histograma → *distribution* | s | + `oficina.work_order.status` | permanência em cada status |
| `oficina.work_order.diagnosis_to_completion.duration` | histograma → *distribution* | s | `env`, `service`, `version` | — |
| `oficina.work_order.lead_time.duration` | histograma → *distribution* | s | `env`, `service`, `version` | — |

**Valores de `oficina.work_order.status` observados**: `received`, `in_diagnosis`, `awaiting_approval`,
`approved`, `in_progress`, `completed` — **em minúsculas**. Ver a limitação L12.

Semântica herdada do ADR 0005 da API, e que muda a leitura dos números:

- Permanência ancora na **última** entrada no status; totais ancoram na **primeira**.
- Status terminais (`DELIVERED`, `CANCELLED`) **não emitem** permanência, o que limita a quebra a sete valores.
- A emissão é *best-effort* pós-commit: **subcontagem silenciosa é possível**. Estes números são indicativos,
  não contábeis.
- Temporalidade delta com intervalo de 60 s: uma exportação que falha perde a janela inteira.

### 2.2 Métricas de instrumentação da API

| Métrica | Tipo | Unidade | Dimensões emitidas |
| --- | --- | --- | --- |
| `http.server.request.duration` | *distribution* | **s** | `http.request.method`, `url.scheme`, `network.protocol.version`, `http.route`, `http.response.status_code`, `error.type` |
| `db.client.operation.duration` | *distribution* | s | `db.system.name`, `db.namespace`, `db.operation.name`, `server.address`, `server.port`, `error.type` |
| `db.client.connection.count` / `.max` / `.pending_requests` | gauge | conexões | `db.client.connection.pool.name`, `db.client.connection.state` (`used`, `idle`) |
| `nodejs.eventloop.delay.{min,max,mean,stddev,p50,p90,p99}`, `.utilization`, `.time` | gauge | s / razão | `nodejs.eventloop.state` |
| `v8js.memory.heap.used`, `v8js.memory.heap.space.{size,physical_size,available_size}`, `v8js.gc.duration` | gauge / *distribution* | bytes / s | `v8js.heap.space.name`, `v8js.gc.type` |

**`http.route` e `http.response.status_code` são a grafia correta** — `http_route`, `http_status_code` e
`status_code` não existem. Rotas preservam `/` e `:` (`/api/work-orders/:id`), e o filtro por prefixo
(`http.route:/api/work-orders*`) funciona.

`error.type` é preenchido **exclusivamente** para respostas 5xx ou erro de transporte. Mesmo assim, nenhuma
consulta o usa: ele foi descartado do índice pela configuração de tags da seção 5, e
`http.response.status_code:5*` é equivalente e mais barato.

### 2.3 Tags de recurso

Conforme o mapeamento oficial OTel → Datadog, aplicável a métricas:

| Atributo OTel | Tag Datadog | Confirmado |
| --- | --- | --- |
| `service.name` | `service` | `oficina-mecanica-api` |
| `deployment.environment.name` | `env` | `production` (exige Agent ≥ 7.58; o cluster roda 7.60) |
| `service.version` | `version` | o SHA do commit |

### 2.4 Kubernetes

Coletadas do *kubelet*, com `kube_deployment:oficina-api`, `pod_name`, `kube_namespace:oficina`,
`kube_container_name:api` e `kube_cluster_name:oficina-mecanica`.

`kubernetes.cpu.usage.total` · `kubernetes.cpu.requests` · `kubernetes.cpu.limits` ·
`kubernetes.cpu.cfs.periods` · `kubernetes.cpu.cfs.throttled.periods` · `kubernetes.memory.working_set` ·
`kubernetes.memory.limits` · `kubernetes.memory.usage_pct` · `kubernetes.containers.restarts` ·
`kubernetes.containers.running` · métricas de nó em `system.*`.

**Cuidado de unidade (L13)**: `kubernetes.cpu.usage.total` vem em **nanocores**; `requests` e `limits` vêm em
**cores**. Sobrepor os três num gráfico exige dividir o primeiro por `1e9`.

### 2.5 Lambda

Métricas *enhanced* da extensão, com `functionname:lbd-oficina-mecanica-customer-auth`, `region`,
`memorysize`, `runtime` e **`cold_start:true|false`**.

`aws.lambda.enhanced.invocations` · `.duration` · `.billed_duration` · `.init_duration` · `.max_memory_used` ·
`.estimated_cost` · e as três de falha: `.errors`, `.timeouts`, `.out_of_memory`.

**As três de falha não existem na conta enquanto nenhuma falha ocorre** — a extensão só as emite no evento.
Ver a limitação L14.

### 2.6 Logs

`service:oficina-mecanica-api`, `env:production`, `source:ecr-oficina-mecanica-app-repo`,
`cluster_name:oficina-mecanica`, `pod_name`, `container_name:api`, `status` derivado de `level`.

Correlação log ↔ trace **funciona sem pipeline customizado**, porque `trace_id` já é um dos atributos de
origem do pré-processamento de JSON do destino.

Facetas confirmadas: `@http.route`, `@http.response.status_code`, `@http.request.method`, `@error.type`,
`@oficina.error.message`, `@oficina.http.server.request.duration_ms`, `@code.function.name`,
`@service.version`, `@request.id`, `@user.id`, `@user.roles`, `@oficina.event.name`,
`@oficina.work_order.status.current`.

Valores de `@oficina.event.name` observados em 30 dias:

| Valor | Ocorrências |
| --- | ---: |
| `app.started` · `db.connected` | 8 cada |
| `app.shutdown` · `auth.authentication.succeeded` · `db.disconnected` | 4 cada |
| `mail.send.succeeded` · `work_order.service.status.updated` · `work_order.status.updated` | 2 cada |
| `customer.access.granted` · `quote.approved` · `quote.submitted` · `stock.consumed` · `stock.reserved` | 1 cada |
| `quote.rejected` · `mail.send.failed` · `health.degraded` | **0** — ver L15 |

### Volume do índice por serviço, na sessão mais recente

| Serviço | Linhas | Fatia |
| --- | ---: | ---: |
| `oficina-mecanica-api` | 982 | **42,2 %** |
| `kube-proxy` | 599 | **25,7 %** |
| `ecr-oficina-mecanica-app-repo` (Job de migração) | 317 | 13,6 % |
| `oficina-mecanica-db-migrate` | 144 | 6,2 % |
| `metrics-server` | 128 | 5,5 % |
| `oficina-mecanica-lambda-customer-auth` | 67 | 2,9 % |
| `coredns` | 40 | 1,7 % |
| `amazon-k8s-cni-init` / `amazon-k8s-cni` | 52 | 2,2 % |
| **Total** | **2 329** | |

`mailhog` e o próprio `agent` **já são excluídos na origem**, por `DD_CONTAINER_EXCLUDE_LOGS` no manifesto do
agente em `oficina-mecanica-app`.

**Meça volume sobre uma sessão, nunca sobre 30 dias.** Todo o índice cabe nas últimas 48 h, e as sessões
anteriores àquela exclusão ainda respondem por 9 374 linhas de `mailhog` — uma janela de 30 dias faz `mailhog`
parecer 70 % do volume atual, quando ele é zero.

Severidade em `service:oficina-mecanica-api`: `info` 959, `warn` 16, `error` 7. Os sete de erro **não carregam**
`@oficina.event.name`: são erros fora do catálogo de eventos de domínio.

---

## 3. Limitações

Cada uma é citada por sigla nos demais documentos e nos comentários do Terraform. A explicação vive aqui.

| # | Limitação | Evidência | Consequência | Gatilho de reavaliação |
| --- | --- | --- | --- | --- |
| **L1** | **Sem Cluster Agent.** `kubernetes_state.*` não existe | `Live Pods → No Results Found → enable Kubernetes resources collection` | Sem réplicas desejadas contra disponíveis, sem `pod.ready`, sem estado de HPA. O widget de réplicas conta pods que **emitem métrica** | Instalar o Cluster Agent no repositório `oficina-mecanica-app` |
| **L2** | **Sem integração AWS no destino** | Ausência de qualquer `aws.*` vindo do CloudWatch | Sem métricas de API Gateway e de RDS. **Impossível, não opcional**: a integração exige criar uma role IAM, e o AWS Academy não permite | Conta AWS fora do laboratório |
| **L3** | **Probes excluídas na entrada** (`ignoreIncomingRequestHook`) | `incoming-request-filter.ts` na API | A rota de saúde não é observável por métrica, trace nem log de sucesso. **Uptime só por verificação externa** | Nenhum — é decisão deliberada da API. A dívida é quitada por [ADR 0003](adr/0003-uptime-por-verificacao-externa.md) |
| **L4** | **`DD_TRACE_ENABLED=false` na Lambda** | `terraform/locals.tf` da Lambda | Sem APM da função: só métricas da extensão e logs | Ligar o traço na Lambda |
| **L5** | **Agent 7.60 < 7.66 → *operation name v1*** | A operação registrada é literalmente `opentelemetry_instrumentation_http.server` | Métricas `trace.*` teriam nome instável, que **mudaria** numa atualização do agente | **Gatilho armado**: há PR aberto em `oficina-mecanica-app` subindo o agente para 7.83.1. No merge, esta limitação deixa de existir e o [ADR 0002](adr/0002-latencia-por-metrica-otlp.md) deve ser reaberto |
| **L6** | **Histogramas OTLP viram *distributions*** | Documentação oficial | `p95` exige habilitar agregações de percentil **por métrica** | — |
| **L7** | **Coleta de log de todo o cluster** | Medido na sessão mais recente: 2 329 linhas, das quais `kube-proxy` **25,7 %**, `metrics-server` 5,5 %, CNI 2,2 %, `coredns` 1,7 % — **~35 % é ruído de plataforma**, e boa parte com severidade `error` porque `klog` escreve em stderr. A API é 42,2 % | Toda consulta de log **escopa por `service`, por inclusão** | Exclusão na origem — ver a seção 6 |
| **L8** | ~~**`env` divergente**: `production` na API, `prod-simulated` na Lambda~~ **RESOLVIDA** | A função emitia `env:prod-simulated`; hoje emite `env:production`, confirmado por `sum:aws.lambda.enhanced.invocations{...} by {env}` | Nenhuma. O monitor da Lambda segue escopado por `functionname`, que é o identificador estável da função | — |
| **L9** | **`version` não é tag de log** | Deployment sem `tags.datadoghq.com/version` | O commit continua consultável como `@service.version` | Acrescentar a anotação no Deployment |
| **L10** | **Ambiente efêmero**: laboratório ligado sob demanda, destruído ao final | Informado pelo time; orçamento de US$ 50 | **Nenhum monitor notifica por ausência de dado.** O endereço público muda a cada reprovisionamento | Ambiente permanente |
| **L11** | **Logs do Job de migração** parcialmente sob `ecr-oficina-mecanica-app-repo` | 144 linhas em `oficina-mecanica-db-migrate` e 619 no repositório de imagem | Consultas de log escopam por serviço **por inclusão**, nunca por exclusão | — |
| **L12** | **Valor de tag de métrica é normalizado para minúsculas; atributo de log não** | `http.request.method` responde `get`/`post`; `@oficina.work_order.status.current` responde `IN_DIAGNOSIS` | O dashboard de Ordens de Serviço exibe as duas grafias, e isso é inerente às duas fontes | — |
| **L13** | **CPU de uso em nanocores, requests e limits em cores** | `usage.total` ~15,2 e6 contra `requests` 0,2 | Comparação exige divisão por `1e9` | — |
| **L14** | **Métricas de falha da Lambda não existem até a primeira falha** | `.errors`, `.timeouts`, `.out_of_memory` sem série em 30 dias | O monitor de erros da Lambda avalia em **`No Data`**, não em `OK`, na operação normal. Não notifica, por `notify_no_data = false` | — |
| **L15** | **Três eventos de log nunca observados**: `quote.rejected`, `mail.send.failed`, `health.degraded` | Zero ocorrências em 30 dias de índice | Os monitores de falha de e-mail e de dependência degradada, e o widget de decisões de orçamento são construídos sobre eventos não observados. **Não podem ser verificados sem provocar o evento na origem** | Exercitar o caminho de exceção |

`api_apm_summary.jpeg` confirma que a conta **não tinha** monitores, testes sintéticos nem objetivos de nível
de serviço antes desta entrega: não houve nada a importar.

---

## 4. Divergências e fonte de verdade

| Divergência | Quem está certo | Regra |
| --- | --- | --- |
| ~~`env`: `production` contra `prod-simulated`~~ **resolvida** | **`production`**, e agora é o único valor emitido | A unificação de `DD_ENV` foi integrada no repositório da Lambda. Consultas da Lambda seguem escopadas por `functionname` — não por dependerem disso, mas porque é o identificador estável da função |
| Status da OS: `IN_DIAGNOSIS` (log) contra `in_diagnosis` (métrica) | **Ambos** — são fontes diferentes | Consulta de métrica usa minúsculas; consulta de log usa o enum de domínio. Nunca converter um no outro numa mesma consulta |
| Nome da operação de trace: `opentelemetry_instrumentation_http.server` | Instável, **não é fonte de verdade** | Latência vem de `http.server.request.duration`, nunca de `trace.*` (L5, [ADR 0002](adr/0002-latencia-por-metrica-otlp.md)) |
| `version` presente em métrica, ausente em log | **Métrica** para filtro; `@service.version` para log | Não existe filtro de log por tag `version` |

---

## 5. Custo de custom metrics

Uma *distribution* custa **5 custom metrics por série**; com percentis habilitados, **10**.

**Uma única métrica** recebe `datadog_metric_tag_configuration`, em `terraform/metrics.tf`:

| Métrica | Tags indexadas | Séries estimadas | Custom metrics |
| --- | --- | ---: | ---: |
| `http.server.request.duration` | `env`, `service`, `http.route`, `http.response.status_code` | 16 rotas × ~6 códigos ≈ **96** | **~960** |

As três métricas de negócio **não** recebem a habilitação: elas continuam consultáveis por `avg`, `max`, `min`,
`sum` e `count`, que são gratuitos, e nenhum monitor depende de percentil sobre elas. Habilitá-las dobraria o
custo de cada uma sem responder nada que o máximo já não responda.

**A alavanca de redução é uma linha.** Remover `http.response.status_code` da lista de
`http.server.request.duration` derruba a estimativa de ~960 para **~160** — total de ~250 — e move "erro por
rota" para os logs, onde `@http.route` e `@http.response.status_code` já são facetas confirmadas. O custo é
perder a série de 5xx por rota no dashboard e a base dos monitores de erros 5xx e de falhas no fluxo de ordens de serviço, que passariam a monitores de log.

Descartado do índice, deliberadamente, e por isso indisponível para consulta de métrica:
`url.scheme`, `network.protocol.version`, `http.request.method`, `version` e `error.type`.

**Consumo real observado**: pendente. A cota do plano só é observável com dado fluindo por uma janela
representativa; a leitura é tarefa da fase de calibração e este número deve ser preenchido aqui.

---

## 6. O que não é responsabilidade deste repositório

- **Instrumentação, agente e extensão.** Alterar o que é coletado é mudança nos repositórios de origem.
- **Índice de logs, filtros de retenção e políticas de restrição.** Não neste primeiro corte.
- **Métricas derivadas de log.** A cardinalidade atual não justifica.
- **Objetivos de nível de serviço.** Um objetivo com janela de 30 dias sobre um ambiente deliberadamente
  desligado na maior parte do tempo produziria um número sem significado. O requisito de *uptime* é atendido
  pela taxa de sucesso do teste sintético na janela do dashboard.

Uma redução de volume de log **na origem** está proposta como tarefa opcional no repositório
`oficina-mecanica-app`. O manifesto do agente já exclui `name:mailhog name:agent`; acrescentar
`name:kube-proxy` elimina outros **~26 %** do que sobrou, e somar `name:metrics-server`, `name:coredns` e
`name:aws-node` chega a **~35 %** — sem perder um único sinal de aplicação.
