# ADR 0002: Latência vem da métrica OTLP, não das *trace metrics* do APM

## Status

Aceito — 2026-09-09

## Contexto

O dashboard de API precisa de p50, p90, p95 e p99 de latência, e o monitor de latência alerta sobre o p95. Há dois caminhos
possíveis na conta, e eles não são equivalentes.

**Caminho 1 — *trace metrics* do APM.** O Agent gera a distribution `trace.<SPAN_NAME>` a partir dos spans,
com percentis disponíveis e sem custo de custom metric. Com o Agent 7.83.1 e o mapeamento v2, a operação HTTP
observada é `http.server.request` e a distribution correspondente é `trace.http.server.request`.

**Caminho 2 — a métrica OTLP `http.server.request.duration`**, emitida por
`@opentelemetry/instrumentation-http` em segundos, com as dimensões `http.route` e
`http.response.status_code`. Por ser um histograma OTLP, ela chega ao destino como uma *distribution*, e
percentis exigem habilitar agregações por métrica — o que **custa custom metrics**.

Os dois caminhos existem na conta, mas têm pipelines e dimensões distintos. A trace distribution é calculada
pelo Agent a partir dos spans recebidos. Amostragem no SDK OpenTelemetry, anterior ao Agent, pode reduzir
sua cobertura; isso não significa que toda trace metric seja calculada apenas sobre traces retidos no APM.
A métrica OTLP é exportada diretamente pela instrumentação, independentemente da amostragem de traces, e
mantém as dimensões `http.route` e `http.response.status_code` usadas pelos dashboards e monitores atuais.

## Decisão

**Latência e erro vêm de `http.server.request.duration`**, com agregações de percentil habilitadas por
`datadog_metric_tag_configuration` em `terraform/metrics.tf`.

O nome de uma métrica OTLP é definido pelas convenções semânticas do OpenTelemetry. A escolha preserva a
fonte não amostrada e as dimensões já indexadas, ao custo de custom metrics.

## Alternativas consideradas

| Alternativa | Por que não |
| --- | --- |
| **`trace.http.server.request` do APM** | Fonte derivada dos spans recebidos pelo Agent; a escolha atual mantém o pipeline de métricas independente do de traces e as dimensões configuradas nos monitores |
| **Percentis a partir de logs** (`@oficina.http.server.request.duration_ms`) | Depende da retenção do índice de logs, tem precisão pior e custo por GB indexado |
| **Só `avg` e `max`, sem habilitar percentis** | Gratuito, mas média esconde a cauda — e p95 é requisito explícito, não preferência. A média de uma rota que responde em 20 ms com 5 % de requisições em 3 s parece saudável |
| **`include_percentiles` sem limitar as tags** | Custo descontrolado: as seis dimensões emitidas multiplicariam as séries indexadas por ordens de grandeza |

## Consequências

- **Custo declarado**: ~96 séries × 10 custom metrics ≈ **960**, com quatro tags indexadas
  (`env`, `service`, `http.route`, `http.response.status_code`). A conta completa está em
  [Observabilidade](../observability.md#5-custo-de-custom-metrics).
- **Cinco dimensões são descartadas do índice**: `url.scheme`, `network.protocol.version`,
  `http.request.method`, `version` e `error.type`. Nenhum widget as consulta — mas isso também significa que
  **quebrar por método HTTP não é possível** enquanto essa configuração vigorar.
- O filtro de erro passa a ser `http.response.status_code:5*` em vez de `error.type`. Os dois são
  equivalentes: `error.type` só é preenchido para 5xx e erro de transporte.
- **A alavanca de redução é uma linha.** Remover `http.response.status_code` derruba a estimativa para ~160 e
  move "erro por rota" para os logs — ao custo de os monitores de erros 5xx e de falhas no fluxo de ordens de serviço virarem monitores de log.
- **As métricas de negócio não recebem a habilitação.** Elas também são histogramas OTLP, mas nenhum monitor
  depende de percentil sobre elas, e para responder "alguma ordem ficou presa neste status?" o **máximo** é
  mais direto que o p95. `avg`, `max`, `min`, `sum` e `count` são gratuitos e bastam.
- **`p95:db.client.operation.duration` e `p95:aws.lambda.enhanced.duration` continuam indisponíveis**, e
  deliberadamente: habilitá-las multiplicaria o custo sem que nenhum monitor dependa delas. Esses widgets usam
  média e máximo, com nota explicando a escolha.

## Reavaliação da fonte

Uma eventual troca da métrica OTLP exige decisão explícita: revisar widgets e consultas, comparar cobertura e dimensões entre as fontes e recalibrar os limiares com dados da fonte escolhida. O upgrade do Agent não migra esses consumidores automaticamente; a decisão vigente continua sendo usar a métrica OTLP.

## Referências

- [Amostragem de ingestão com OpenTelemetry](https://docs.datadoghq.com/opentelemetry/ingestion_sampling/)
