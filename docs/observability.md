# Observabilidade

Documento âncora deste repositório. Inventaria **o que a solução realmente emite** e, com o mesmo cuidado,
**o que ela não emite** — porque metade das perguntas de revisão sobre um dashboard é "por que isto não está
aqui?", e a resposta precisa estar escrita em um só lugar.

Os sinais são definidos pelo código da API, pelos manifests de coleta e pelo Terraform dos componentes.
Este documento descreve seus contratos e a configuração consumida pelo monitoramento no site `us5`.

---

## 1. Como o sinal chega ao destino

| Origem | Caminho | O que chega |
| --- | --- | --- |
| API (NestJS, pods no EKS) | SDK OpenTelemetry → exportador OTLP → Datadog Agent 7.83.1 (DaemonSet) | métricas e traces por OTLP; logs pelo stdout dos contêineres |
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

As *trace metrics* vigentes usam as operações `http.server.request` para HTTP e `postgresql.query` para
PostgreSQL; as séries anteriores baseadas nos escopos de instrumentação não fazem parte do contrato atual.
A métrica de latência atual do APM é a *distribution* `trace.<SPAN_NAME>`; a forma
`trace.<SPAN_NAME>.duration` é legada e não oferece percentis. Dashboards e monitores continuam usando
`http.server.request.duration`, conforme os critérios do
[ADR 0002](adr/0002-latencia-por-metrica-otlp.md).

### 2.3 Tags de recurso

Conforme o mapeamento oficial OTel → Datadog, aplicável a métricas:

| Atributo OTel | Tag Datadog | Confirmado |
| --- | --- | --- |
| `service.name` | `service` | `oficina-mecanica-api` |
| `deployment.environment.name` | `env` | `production` |
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

O logger instrumentado da API inclui `trace_id`, `span_id` e `trace_flags` quando existe contexto de span
ativo. O access log também contém `request.id`. Logs de inicialização de módulos e dependências do NestJS,
bootstrap e encerramento fora de spans não recebem identificadores sintéticos de trace.

O contrato é implementado em `trace-correlation.ts` e no `mixin` de `logging.module.ts`, com os campos
permitidos pelo registro do logger. Logs de `metrics-server` e do Job `oficina-mecanica-db-migrate` pertencem
a outros produtores e não são evidência de falha de correlação do logger da API.

O [pré-processamento de JSON do Datadog](https://docs.datadoghq.com/logs/log_configuration/pipelines/)
reconhece `trace_id` e `span_id` como atributos de correlação; a ausência deles entre atributos customizados
de uma resposta de busca, isoladamente, não comprova ausência de correlação. A navegação log ↔ trace também
depende de o trace correspondente estar disponível no destino.

No Log Explorer e na API de busca, esses identificadores são campos reservados: use `trace_id:*` e
`span_id:*`, sem o prefixo `@`. `@request.id:*` continua sendo uma busca por atributo customizado.
Para investigar correlação, filtre o serviço da API e diferencie access logs e eventos com span ativo
dos logs de ciclo de vida e das falhas de healthcheck, cujas requests são excluídas da instrumentação.

Facetas confirmadas: `@http.route`, `@http.response.status_code`, `@http.request.method`, `@error.type`,
`@oficina.error.message`, `@oficina.http.server.request.duration_ms`, `@code.function.name`,
`@service.version`, `@request.id`, `@user.id`, `@user.roles`, `@oficina.event.name`,
`@oficina.work_order.status.current`.

Os catálogos da API definem eventos de ciclo de vida, autenticação, estoque, orçamento, ordens de serviço,
envio de e-mail e dependências. Dashboards e monitores filtram `@oficina.event.name` conforme a pergunta
operacional; uma contagem vazia não significa que o caminho correspondente não exista na implementação.

O manifesto do Agent exclui os logs de `mailhog`, do próprio `agent` e de `kube-proxy` por
`DD_CONTAINER_EXCLUDE_LOGS`. `metrics-server`, `coredns` e `aws-node` continuam coletados porque suas falhas
são sinais da plataforma.

---

## 3. Limitações

Cada uma é citada por sigla nos demais documentos e nos comentários do Terraform. A explicação vive aqui.

| # | Limitação | Evidência | Consequência | Tratamento atual |
| --- | --- | --- | --- | --- |
| **L1** | **Sem Cluster Agent.** `kubernetes_state.*` não existe | `Live Pods → No Results Found → enable Kubernetes resources collection` | Sem réplicas desejadas contra disponíveis, sem `pod.ready`, sem estado de HPA | O dashboard conta pods que emitem métrica; não apresenta essa contagem como prontidão |
| **L2** | **Sem integração AWS no destino** | Ausência de `aws.*` vindo do CloudWatch | Sem métricas de API Gateway e de RDS | O ambiente AWS Academy não permite criar a role exigida pela integração |
| **L3** | **Probes excluídas na entrada** (`ignoreIncomingRequestHook`) | `incoming-request-filter.ts` na API | A rota de saúde não produz métrica, trace nem log de sucesso | Uptime vem do teste sintético externo definido em `synthetics.tf` |
| **L4** | **Lambda com coleta sem instrumentação APM** | Extensão habilitável, `DD_TRACE_ENABLED=false`, sem SDK ou wrapper de tracing | Sem spans internos da função | Os dashboards usam métricas enhanced e logs, conforme a decisão do [ADR 0005 da Lambda](https://github.com/FIAP-15SOAT/oficina-mecanica-lambda-customer-auth/blob/main/docs/adr/0005-coleta-de-telemetria-sem-instrumentacao.md) |
| **L6** | **Histogramas OTLP viram *distributions*** | Configuração Datadog da métrica | `p95` exige agregações de percentil por métrica | `metrics.tf` habilita percentis somente para `http.server.request.duration` |
| **L7** | **Coleta de logs de plataforma** | `DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true` | Consultas sem escopo misturam aplicação e componentes do cluster | O Agent exclui `mailhog`, `agent` e `kube-proxy`; consultas usam `service` por inclusão |
| **L9** | **`version` não é tag de log** | Deployment sem `tags.datadoghq.com/version` | Não existe filtro de log pela tag `version` | O valor permanece consultável como atributo `@service.version` |
| **L10** | **Ambiente efêmero** | Laboratório ligado sob demanda e destruído ao final | Ausência de dado é normal e o endpoint público muda a cada provisão | Monitores usam `notify_no_data = false`; o teste sintético alterna entre `live` e `paused` |
| **L12** | **Valor de tag de métrica é normalizado para minúsculas; atributo de log não** | `http.request.method` responde `get`/`post`; `@oficina.work_order.status.current` responde `IN_DIAGNOSIS` | O dashboard de Ordens de Serviço exibe as duas grafias | Consultas preservam a grafia de cada fonte |
| **L13** | **CPU de uso em nanocores, requests e limits em cores** | `usage.total` em nanocores; `requests` em cores | Comparação direta distorce a escala | Widgets dividem o uso por `1e9` |
| **L14** | **Métricas de falha da Lambda dependem da ocorrência da falha** | `.errors`, `.timeouts`, `.out_of_memory` são sinais de evento da extensão | Sem ocorrências, a consulta pode retornar `No Data`, não necessariamente `OK` | `notify_no_data = false` evita alerta por ausência normal da série |
| **L16** | **O funil mede saídas de status, não um único evento de atualização** | `dashboard_work_orders.tf` consulta o histograma de permanência | Não interpreta `work_order.status.updated` como contador universal de transições | Usa `count:oficina.work_order.status.duration by {oficina.work_order.status}` |
| **L15** | **Eventos condicionais**: `quote.rejected`, `mail.send.failed`, `health.degraded` | Emitidos somente pelos caminhos correspondentes da aplicação | Widgets podem ficar vazios sem recusa ou falha no intervalo selecionado | Consultas usam o catálogo da API; ausência de ocorrência não é ausência de implementação |

---

## 4. Divergências e fonte de verdade

| Divergência | Quem está certo | Regra |
| --- | --- | --- |
| Status da OS: `IN_DIAGNOSIS` (log) contra `in_diagnosis` (métrica) | **Ambos** — são fontes diferentes | Consulta de métrica usa minúsculas; consulta de log usa o enum de domínio. Nunca converter um no outro numa mesma consulta |
| Trace distribution `trace.http.server.request` contra métrica OTLP `http.server.request.duration` | **Ambas existem**, com origem e semântica de amostragem diferentes | Dashboards e monitores usam a métrica OTLP, conforme [ADR 0002](adr/0002-latencia-por-metrica-otlp.md) |
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

---

## 6. O que não é responsabilidade deste repositório

- **Instrumentação, agente e extensão.** Alterar o que é coletado é mudança nos repositórios de origem.
- **Índice de logs, filtros de retenção e políticas de restrição.** Não neste primeiro corte.
- **Métricas derivadas de log.** A cardinalidade atual não justifica.
- **Objetivos de nível de serviço.** Um objetivo com janela de 30 dias sobre um ambiente deliberadamente
  desligado na maior parte do tempo produziria um número sem significado. O requisito de *uptime* é atendido
  pela taxa de sucesso do teste sintético na janela do dashboard.

O manifesto do Agent exclui atualmente `name:mailhog name:agent name:kube-proxy`.
`name:metrics-server`, `name:coredns` e `name:aws-node` permanecem coletados para preservar sinais da plataforma.
