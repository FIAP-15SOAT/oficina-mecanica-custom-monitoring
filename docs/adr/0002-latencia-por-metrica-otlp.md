# ADR 0002: Latência vem da métrica OTLP, não das *trace metrics* do APM

## Status

Aceito — 2026-09-09

## Contexto

O dashboard de API precisa de p50, p90, p95 e p99 de latência, e M3 alerta sobre o p95. Há dois caminhos
possíveis na conta, e eles não são equivalentes.

**Caminho 1 — *trace metrics* do APM.** O agente gera automaticamente `trace.<operação>.duration` a partir dos
spans, **com percentis já disponíveis e sem custo de custom metric**. É o caminho que a documentação do
fornecedor recomenda, e seria o mais barato.

**Caminho 2 — a métrica OTLP `http.server.request.duration`**, emitida por
`@opentelemetry/instrumentation-http` em segundos, com as dimensões `http.route` e
`http.response.status_code`. Por ser um histograma OTLP, ela chega ao destino como uma *distribution*, e
percentis exigem habilitar agregações por métrica — o que **custa custom metrics**.

O caminho 1 parece melhor até você olhar o nome da operação registrada na conta. Ele é, literalmente:

```
opentelemetry_instrumentation_http.server
```

Não é um apelido nem uma abreviação da interface: é o nome do escopo de instrumentação, promovido a nome de
operação. O agente do cluster roda a versão **7.60**, e a lógica de nomeação de operação **v2** — que produziria
`http.server.request` — só entra a partir da **7.66**.

A métrica correspondente se chamaria `trace.opentelemetry_instrumentation_http.server.duration`, e ela é duas
coisas ao mesmo tempo:

- **ilegível** — ninguém lê esse nome num título de widget e entende o que está vendo;
- **instável** — atualizar o agente para ≥ 7.66 a **renomearia**, quebrando em silêncio todo dashboard e todo
  monitor construído sobre ela. O alerta não erraria: ele simplesmente pararia de avaliar.

## Decisão

**Latência e erro vêm de `http.server.request.duration`**, com agregações de percentil habilitadas por
`datadog_metric_tag_configuration` em `terraform/metrics.tf`.

O nome de uma métrica OTLP é definido pela especificação de convenções semânticas do OpenTelemetry, e **não
muda com a versão do agente**. É essa estabilidade que se está comprando com o custo de custom metrics.

## Alternativas consideradas

| Alternativa | Por que não |
| --- | --- |
| **`trace.<operação>.*` do APM** | Nome derivado do escopo de instrumentação e **instável entre versões do agente**. Gratuito, mas o preço é uma quebra silenciosa numa atualização de rotina |
| **Percentis a partir de logs** (`@oficina.http.server.request.duration_ms`) | Depende da retenção do índice de logs, tem precisão pior e custo por GB indexado. Fica registrado como o fallback caso a alavanca de custo precise ser acionada |
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
  move "erro por rota" para os logs — ao custo de M2 e M4 virarem monitores de log.
- **As métricas de negócio não recebem a habilitação.** Elas também são histogramas OTLP, mas nenhum monitor
  depende de percentil sobre elas, e para responder "alguma ordem ficou presa neste status?" o **máximo** é
  mais direto que o p95. `avg`, `max`, `min`, `sum` e `count` são gratuitos e bastam.
- **`p95:db.client.operation.duration` e `p95:aws.lambda.enhanced.duration` continuam indisponíveis**, e
  deliberadamente: habilitá-las multiplicaria o custo sem que nenhum monitor dependa delas. Esses widgets usam
  média e máximo, com nota explicando a escolha.

## Gatilho de reavaliação

**O agente do cluster subir para ≥ 7.66.** Há um Pull Request aberto e não aprovado no repositório
`oficina-mecanica-app` subindo a imagem de `7.60.0` para `7.83.1` — **o gatilho dispara no merge dele**.

Quando a operação passar a se chamar `http.server.request`, `trace.http.server.request.*` vira um nome estável
e legível, com percentis **gratuitos**. Nesse dia esta decisão deve ser reaberta: migrar latência para as
*trace metrics* eliminaria ~960 custom metrics, que é praticamente todo o custo deste repositório.

**A migração não é automática nem barata.** Ela reescreve o grupo de Latência e a tabela de rotas do dashboard
de API, a consulta de M3, e torna `terraform/metrics.tf` desnecessário. Também troca a fonte do dado: *trace
metrics* são amostradas e a métrica OTLP não é, então os números não são idênticos e os limiares de M3
precisariam ser recalibrados sobre a nova fonte.

Por isso o gatilho fica registrado aqui, como decisão a tomar, e não como pendência a executar. O que **não**
muda com a atualização: o nome `http.server.request.duration` continua definido pela convenção semântica do
OpenTelemetry e segue estável — a configuração atual não quebra.
