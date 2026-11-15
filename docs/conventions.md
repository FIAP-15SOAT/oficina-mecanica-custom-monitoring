# Convenções

Nomenclatura, tagging e os nomes de sinal que as consultas deste repositório usam. Curto de propósito: uma
convenção que ninguém lembra não é seguida.

A solução tem quatro serviços NestJS, cada um com o nome do seu contexto de negócio: `work-order` (ordens de
serviço, clientes e veículos), `identity` (usuários e login), `billing` (orçamentos e cobranças) e `inventory`
(serviços, peças e estoque). Tem também duas funções Lambda: a `customer-auth` (login do cliente) e a
`notification` (envio de e-mail).

---

## Nomes exibidos no Datadog

| Tipo | Padrão | Exemplos |
| --- | --- | --- |
| Dashboard | `Oficina Mecânica · <Área>` | `Oficina Mecânica · Visão Geral`, `Oficina Mecânica · Serviço billing`, `Oficina Mecânica · Sagas` |
| Monitor | `[Oficina Mecânica] <Componente> · <Sintoma>` | `[Oficina Mecânica] Serviço billing · Erros 5xx acima do limite`, `[Oficina Mecânica] Pod inventory · Memória próxima do limite`, `[Oficina Mecânica] Mensageria · Mensagem na DLQ` |
| Teste sintético | mesmo padrão de monitor | `[Oficina Mecânica] Disponibilidade externa identity · rota pública indisponível` |

O separador é o **ponto médio** `·` (U+00B7), não hífen. Os colchetes existem só nos monitores, porque o
assunto do e-mail começa pelo nome do monitor e o prefixo entre colchetes é o que separa esta solução de
qualquer outra na caixa de entrada.

**O sintoma nomeia o que está errado, não a métrica.** `Memória próxima do limite`, não
`kubernetes.memory.working_set alto`. Quem recebe o alerta precisa saber o que está acontecendo antes de saber
de onde veio o número.

### Nomes por serviço

O que se repete por serviço ou por Lambda leva a **chave do mapa** no nome: o contexto (`work-order`,
`identity`, `billing`, `inventory`) ou o nome curto da função (`customer-auth`, `notification`). Os mapas
estão descritos em [Infraestrutura](terraform.md#os-mapas-de-serviços-e-de-lambdas).

| Repetido por | Nome exibido | Endereço no Terraform |
| --- | --- | --- |
| Serviço | `Oficina Mecânica · Serviço <contexto>` | `datadog_dashboard.service["<contexto>"]` |
| Serviço | `[Oficina Mecânica] Serviço <contexto> · <Sintoma>` | `datadog_monitor.service_5xx["<contexto>"]` |
| Serviço | `[Oficina Mecânica] Pod <contexto> · <Sintoma>` | `datadog_monitor.pod_memory["<contexto>"]` |
| Serviço | `[Oficina Mecânica] Disponibilidade externa <contexto> · rota pública indisponível` | `datadog_synthetics_test.service_health["<contexto>"]` |
| Lambda | `[Oficina Mecânica] Lambda <função> · Erros de execução` | `datadog_monitor.lambda_errors["<função>"]` |

Buscar `Oficina Mecânica` na lista de dashboards ou de monitores traz todos os recursos da solução, e nenhum
recurso da solução fica de fora.

---

## Tags dos recursos criados

Todo recurso carrega, no mínimo:

```
project:oficina-mecanica
managed-by:terraform
env:production
```

Recursos ligados a um componente carregam também `service:<serviço>`:

| Recurso | Tag de serviço |
| --- | --- |
| Teste sintético e monitores de erros 5xx, latência p95, memória e reinícios de pod e health check de cada serviço | o `service` do próprio serviço, por exemplo `service:oficina-mecanica-billing-service` |
| Falhas no fluxo de ordens de serviço | os dois donos das rotas que ele observa: `service:oficina-mecanica-work-order-service` e `service:oficina-mecanica-billing-service` |
| Webhook com assinatura inválida | `service:oficina-mecanica-billing-service` |
| Compensações da aprovação de orçamento | `service:oficina-mecanica-work-order-service` |
| Erros de execução de cada Lambda | o `service` da função, por exemplo `service:oficina-mecanica-lambda-customer-auth` |
| Falha de envio de e-mail | `service:oficina-mecanica-lambda-notification` |
| Mensagem na DLQ, relay do outbox parado e falha na limpeza do cache | **nenhuma** |

**Os três monitores sem tag de serviço** são um monitor só para os quatro serviços, agrupado por `service`.
Marcá-los com os quatro serviços faria todas as linhas "Monitores do serviço" da Visão Geral ficarem vermelhas
quando um único serviço alerta; sem a tag, eles aparecem em "Monitores da solução", e o alerta nomeia o
serviço afetado.

**Dashboards são a exceção, e ela é imposta pelo destino.** A API de dashboards aceita **apenas** as chaves
`team` e `ai`; qualquer outra devolve `400 Invalid tag format. Valid tag keys are: team, ai.` Os dez
dashboards carregam, portanto, só `team:oficina-mecanica`, em `local.dashboard_tags`. Monitor e teste
sintético não têm essa restrição e seguem a regra completa acima.

O que se perde: filtrar a conta por `project:oficina-mecanica` **não** traz os dashboards. O que os mantém
agrupados é a convenção de nome (`Oficina Mecânica · <Área>`) e a tag `team`.

Em `terraform/locals.tf`: `local.common_tags`, `local.service_tags` (mapa por contexto) e `local.lambda_tags`
(mapa por função). Nenhum recurso declara tags à mão.

**`env:production` na tag do recurso é o ambiente da solução.** Os monitores das Lambdas consultam
`functionname:<nome da função>`, que já identifica a função sem ambiguidade.

Filtrar a conta por `project:oficina-mecanica` lista todos os monitores e testes sintéticos da solução, que é
o que o widget "Monitores da solução" da Visão Geral usa; o widget "Monitores do serviço" de cada linha filtra
por `service:<serviço>`. Dashboards ficam de fora por causa da restrição acima; para eles, o filtro é
`team:oficina-mecanica`.

---

## Dimensões de consulta

**Reutilize as dimensões que a instrumentação já produz. Não crie taxonomia paralela.**

| Dimensão | Onde vale |
| --- | --- |
| `env`, `service`, `version` | métricas dos serviços |
| `http.route`, `http.response.status_code` | `http.server.request.duration`, depois da configuração de tags |
| `server.address`, `http.response.status_code` | `http.client.request.duration`, a duração das chamadas HTTP que um serviço faz a outro serviço ou ao Mercado Pago; `server.address` é o host de destino |
| `oficina.work_order.status` | métricas de ordem de serviço (valores em **minúsculas**) |
| `oficina.saga.type` (`QUOTE_APPROVAL`, `PAYMENT`), `oficina.saga.outcome` (`completed`, `compensated`) | métricas de Saga do work-order |
| `oficina.payment.status` (`APPROVED`, `REJECTED`, `EXPIRED`, `CANCELLED`) | `oficina.payment.resolved`, do billing |
| `outcome` | `oficina.messaging.consumed` (`success`, `retry`, `dead_lettered`) e `oficina.payment.webhook.received` (`valid`, `invalid_signature`) |
| `messaging.destination.name` | `oficina.messaging.consumed`: a fila SQS consumida, como `inventory.fifo` |
| `db.operation.name`, `db.client.connection.state` | métricas de banco |
| `kube_namespace`, `kube_deployment`, `pod_name`, `kube_cluster_name` | métricas de Kubernetes; cada serviço roda no namespace com o nome do contexto, e o Datadog Agent e o MailHog (o servidor de e-mail de teste) no `platform` |
| `functionname`, `cold_start`, `region` | métricas das Lambdas |
| `@oficina.event.name`, `@oficina.work_order.status.current`, `@http.route` | facetas de log (valores no **enum de domínio**, maiúsculo) |
| `@oficina.saga.type`, `@oficina.saga.failure_reason` | evento `saga.compensated` |
| `@messaging.destination.name`, `@oficina.messaging.message.type` | evento `messaging.message.dead_lettered` |
| `@oficina.dependency.name`, `@oficina.health.failure.category` | evento `health.degraded` |
| `@oficina.notification.failure.reason`, `@oficina.notification.purpose`, `@oficina.notification.outcome` | eventos `notification.sent` e `notification.failed` da Lambda notification |

Uma consulta escrita com uma dimensão que a instrumentação não produz **é rejeitada na revisão**, e a dimensão
correta é localizada na instrumentação antes do merge. O inventário completo, com valores observados, está em
[Observabilidade](observability.md).

### Sinais da solução distribuída

Os nomes abaixo foram conferidos nos catálogos de cada repositório antes de entrar numa consulta. Os caminhos
são relativos ao `app/src/` do repositório. As métricas de negócio são declaradas em
`application/metrics/business-metric.catalog.ts` sem o prefixo `oficina.`, que só
`infrastructure/telemetry/metric-registry.ts` acrescenta.

| Nome | Tipo | Emitido por | Catálogo |
| --- | --- | --- | --- |
| `oficina.saga.started`, `oficina.saga.finished`, `oficina.saga.duration` | métricas | work-order | `application/metrics/business-metric.catalog.ts` |
| `saga.started`, `saga.completed`, `saga.compensated` | eventos de log | work-order | `application/logging/business-event.catalog.ts` |
| `oficina.payment.requested`, `oficina.payment.resolved` | métricas | billing | `application/metrics/business-metric.catalog.ts` |
| `oficina.payment.webhook.received` | métrica | billing | `infrastructure/http/guards/mercado-pago-signature.guard.ts` |
| `payment.webhook.invalid_signature` | evento de log | billing | `infrastructure/logging/technical-event.catalog.ts` |
| `quote.approved`, `quote.rejected` | eventos de log | billing | `application/logging/business-event.catalog.ts` |
| `oficina.messaging.consumed` | métrica | work-order, billing e inventory | `infrastructure/messaging/sqs-consumer.service.ts` |
| `messaging.message.dead_lettered` | evento de log | work-order, billing e inventory | `infrastructure/logging/technical-event.catalog.ts` |
| `messaging.outbox.publish_failed`, `cache.unavailable`, `cache.invalidation_failed`, `health.degraded` | eventos de log | os quatro serviços | `infrastructure/logging/technical-event.catalog.ts` |
| `notification.sent`, `notification.failed` | eventos de log | Lambda notification | `application/logging/business-event.catalog.ts` |

O identity não consome fila, por isso não emite `oficina.messaging.consumed` nem
`messaging.message.dead_lettered`. `http.client.request.duration` não tem catálogo: vem da instrumentação HTTP
do OpenTelemetry, igual nos quatro serviços.

---

## Escopo de consulta

- **Nunca curinga irrestrito.** Toda consulta de métrica escopa por `env` e `service`, ou pela dimensão
  equivalente do componente (`kube_namespace` e `kube_deployment`, `functionname`, `kube_cluster_name`).
- **Toda consulta de log escopa por `service`, por inclusão.** Nunca por exclusão: o índice recebe sinais de
  vários componentes do cluster e listar o que não se quer é uma lista que envelhece (L7).
- **Vírgula é `AND`, e o destino recusa a mistura de `,` com `AND`/`OR` no mesmo escopo**
  (`'AND' and 'OR' cannot be mixed with ','`). Onde a consulta precisar de `OR`, a expressão inteira troca
  vírgulas por `AND` explícito. É o caso de `local.services_scope`, que cobre os quatro serviços:
  `env:production AND (service:<work-order> OR service:<identity> OR service:<billing> OR service:<inventory>)`.
- **Uma variável de template não entra numa expressão com `OR`.** O dashboard de Kubernetes filtra por
  namespace com a variável `$kube_namespace`, cujos valores padrão são os cinco namespaces; o destino une
  esses valores com `OR` sozinho, então o escopo fica só com vírgulas:
  `kube_cluster_name:oficina-mecanica,$kube_namespace`.

Os escopos ficam em `terraform/locals.tf`, por chave: `local.service_scope["billing"]` (métrica),
`local.service_log_scope["billing"]` (log), `local.service_k8s_scope["billing"]` (Kubernetes) e
`local.lambda_scope["notification"]`.

---

## Arquivos e recursos Terraform

Um arquivo por família. Sem módulos: um ambiente e um consumidor de cada definição não os justificam, e o
reuso real cabe em `locals` e em `for_each`.

```
terraform/
├── backend.tf                  estado remoto
├── providers.tf                providers
├── data.tf                     o state remoto do gateway
├── variables.tf                entradas, incluindo todos os limiares
├── locals.tf                   mapas de serviços e de Lambdas, escopos, tags, links e as mensagens
├── outputs.tf                  endereços dos dashboards e identificadores
├── metrics.tf                  datadog_metric_tag_configuration
├── synthetics.tf               verificação externa, um teste por serviço
├── dashboard_overview.tf       ┐
├── dashboard_service.tf        │ um arquivo por dashboard;
├── dashboard_work_orders.tf    │ o de serviço gera um
├── dashboard_kubernetes.tf     │ dashboard por serviço
├── dashboard_sagas.tf          │
├── dashboard_payments.tf       │
├── dashboard_messaging.tf      ┘
├── monitors_service.tf         erros 5xx, latência p95 (por serviço)
├── monitors_work_orders.tf     falhas no fluxo de ordens de serviço
├── monitors_kubernetes.tf      memória e reinícios de pod (por serviço)
├── monitors_lambda.tf          erros de execução (por Lambda)
├── monitors_integrations.tf    envio de e-mail, health check (por serviço)
├── monitors_messaging.tf       mensagem na DLQ, relay do outbox parado
├── monitors_payments.tf        webhook com assinatura inválida
├── monitors_sagas.tf           compensações da aprovação de orçamento
└── monitors_cache.tf           falha na limpeza do cache
```

| Elemento | Padrão | Exemplo |
| --- | --- | --- |
| Arquivo de dashboard | `dashboard_<área>.tf` | `dashboard_work_orders.tf` |
| Arquivo de monitores | `monitors_<família>.tf` | `monitors_messaging.tf` |
| Nome do recurso | `snake_case`, descrevendo o **sintoma** | `datadog_monitor.pod_memory`, `datadog_monitor.dead_lettered` |
| Variável de limiar | `<componente>_<sinal>_<severidade>_<unidade>` | `api_latency_p95_warning_seconds`, `pod_memory_critical_percent` |
| Local de escopo | `<componente>_scope`, mapa por chave quando se repete | `local.service_scope["billing"]`, `local.services_scope` |
| Local de link de log | `logs_url_<assunto>` | `local.logs_url_health["billing"]`, `local.logs_url_dead_lettered` |

**Nomes de recurso não repetem o tipo.** `datadog_monitor.pod_memory`, não
`datadog_monitor.pod_memory_monitor`.

**Um local usado por um só arquivo fica nesse arquivo**, num bloco `locals` no topo, como as URLs de log de
`monitors_messaging.tf` e o escopo de `dashboard_kubernetes.tf`. `locals.tf` guarda só o que vários arquivos
usam.

---

## Idioma

- **Descrições de variável e nomes de recurso** seguem o inglês dos demais repositórios de infraestrutura da
  solução.
- **Comentários de código** são em inglês nos arquivos mais recentes, como nos demais repositórios; parte dos
  comentários mais antigos ainda está em português.
- **Tudo que o Datadog exibe** — título de dashboard, nome de monitor, título de widget, nota, mensagem de
  alerta — **é em português**, porque o público é o time.
- **Documentação**: português.

---

## O que a revisão de um Pull Request exige

1. Todo nome de métrica, tag e faceta **confirmado por consulta que devolve dados**, ou, para um sinal que a
   aplicação só emite na falha, no catálogo do repositório que o emite.
2. Consulta de alerta validada em `POST /api/v1/monitor/validate` antes do HCL.
3. Nome e tags conforme este documento.
4. Widget com `live_span`, título com unidade e uma só dimensão de quebra, ou duas quando a segunda é o
   resultado (fila e resultado, destino e status).
5. Documentação atualizada no documento certo, **sem duplicar consulta** que já viva em outro.
6. `terraform fmt -check -recursive` e `terraform validate` passando — o CI reprova sem eles.
7. Para monitor novo: a resposta à pergunta "o que a pessoa faz ao receber este e-mail?" escrita em
   [Monitores](monitors.md), e um item no [Runbook](runbook.md).
