# ADR 0006: Monitoramento por serviço e da solução distribuída

## Status

Aceito — 2026-11-15

## Contexto

O monitoramento deste repositório nasceu para um serviço só: um dashboard daquele serviço, monitores escopados por
variáveis com o nome daquele serviço e do Deployment dele, e um teste sintético na rota de saúde dele. A
solução passou a ter quatro serviços NestJS — `work-order` (ordens de serviço, clientes e veículos),
`identity` (usuários e login), `billing` (orçamentos e cobranças) e `inventory` (serviços, peças e estoque) —
e duas funções Lambda, a `customer-auth` (login do cliente) e a `notification` (envio de e-mail).

Três mudanças pedem decisão:

1. **O que era de um serviço passa a ser de quatro.** Cada serviço tem as mesmas perguntas — está de pé, está
   lento, o pod tem folga, a dependência responde — e o mesmo padrão de nomes: `service` =
   `oficina-mecanica-<contexto>-service`, Deployment `<contexto>-service` no namespace `<contexto>`, rota
   pública `/health/<contexto>` no gateway.
2. **Aparecem efeitos que atravessam serviços.** Os serviços trocam comandos e eventos por um tópico SNS e por
   filas SQS FIFO; cada um publica pelo padrão outbox (grava a mensagem numa tabela do próprio banco, na mesma
   transação, e um laço a publica depois); a aprovação de orçamento e o pagamento são Sagas, transações
   conduzidas pelo work-order que são desfeitas (compensadas) quando um passo falha; e o billing recebe o
   resultado das cobranças do Mercado Pago por webhook. Uma mensagem presa deixa uma ordem de serviço parada
   sem que nenhum serviço devolva erro HTTP.
3. **A integração AWS do Datadog não existe no laboratório** (L2 em [Observabilidade](../observability.md)).
   Não chegam profundidade de fila, idade da mensagem mais antiga nem métricas de SNS, RDS ou ElastiCache.

## Decisão

**1. Dois mapas em `locals.tf` são a fonte única do escopo, e tudo que se repete é `for_each` sobre eles.**
O mapa `services` tem uma chave por contexto, que é também o namespace e o segmento da rota de saúde, com o
`service` e o `kube_deployment` de cada um; o mapa `lambdas` tem o nome da função e o `service` de cada Lambda.
Dashboard de serviço, monitores de erros 5xx, latência p95, memória e reinícios de pod e health check, teste
sintético e monitor de erros das Lambdas são um bloco cada, com `for_each`. Os recursos que eram de um serviço
só foram recriados nos endereços novos, sem `moved`. O ambiente, o cluster e os limiares continuam variáveis.

**2. Os sinais da solução distribuída vêm do que as aplicações emitem**, não de métricas da AWS:

- a métrica `oficina.messaging.consumed`, por fila e resultado, para o consumo das filas;
- o evento `messaging.message.dead_lettered`, que o consumidor registra ao desistir de uma mensagem, para a DLQ;
- o evento `messaging.outbox.publish_failed`, que o relay registra a cada ciclo com falha, para o outbox;
- as métricas `oficina.saga.*` e `oficina.payment.*` e os eventos `saga.compensated`,
  `payment.webhook.invalid_signature` e `cache.invalidation_failed`.

Cada nome foi conferido no catálogo do repositório que o emite, e a tabela fica em
[Convenções](../conventions.md#sinais-da-solução-distribuída). Daí saem os dashboards de Sagas, Pagamentos e
Mensageria e os monitores de mensagem na DLQ, relay do outbox parado, webhook com assinatura inválida,
compensações da aprovação de orçamento e falha na limpeza do cache.

**3. Um teste sintético por serviço, na rota `/health/<contexto>`**, com o mesmo controle por
`ENVIRONMENT_ONLINE`, as mesmas localidades e o mesmo quórum ([ADR 0003](0003-uptime-por-verificacao-externa.md)).

## Alternativas

### Para os mapas e o `for_each` (decisão 1)

| Alternativa | Trade-off | Rever se |
| --- | --- | --- |
| **Mapas como variáveis**, com os valores em `terraform.tfvars` | Permitiria trocar os nomes sem editar `locals.tf`, mas repete os mesmos valores na declaração, no `terraform.tfvars` e no `terraform.tfvars.example` — e o `.example` já tinha divergido do nome real do Deployment — para um conjunto que não muda por ambiente | A solução ganhar um segundo ambiente com nomes diferentes |
| **Um arquivo por serviço** | Cada serviço poderia divergir quando precisasse, ao custo de quatro cópias que divergem sem querer e quadruplicam a revisão | Um serviço precisar de dashboard ou monitor que os outros não têm |
| **Módulo Terraform** | Encapsularia o conjunto por serviço, mas o diff de um Pull Request mostraria um parâmetro de módulo, não a consulta alterada ([ADR 0001](0001-terraform-com-provider-datadog.md)) | A solução ganhar vários ambientes com o mesmo conjunto |
| **Um dashboard de serviço único, com seletor `$service`** | Um recurso só, mas a Visão Geral, o resumo da entrega e o link de cada alerta abririam o serviço padrão do seletor, não o degradado | O destino aceitar um link que fixe o valor do seletor em todos esses lugares |
| **Blocos `moved`** levando os recursos atuais para as chaves `work-order` e `customer-auth` | Preservariam identificadores, URLs e histórico; mas o ambiente é efêmero, o Datadog não guarda dado real deste projeto e os blocos seriam apagados depois do primeiro `apply` | O Datadog passar a guardar histórico ou link que não possa ser perdido |

### Para os sinais da aplicação (decisão 2)

| Alternativa | Trade-off | Rever se |
| --- | --- | --- |
| **Integração AWS do Datadog** | Daria profundidade de fila, idade da mensagem mais antiga e métricas de SNS, RDS e ElastiCache sem depender do código; está bloqueada no laboratório, que não permite criar a role exigida | O ambiente permitir a integração: a profundidade da DLQ passa a ser o sinal mais direto e o monitor por evento pode sair |
| **Data Streams Monitoring** | Mediria latência e vazão de ponta a ponta entre produtor e consumidor, mas exige a biblioteca `dd-trace`, e os serviços usam OpenTelemetry | Os serviços adotarem `dd-trace`, ou o recurso aceitar instrumentação OpenTelemetry |
| **Falha do outbox só no dashboard de Mensageria** | Menos um monitor, já que o relay tenta de novo sozinho; mas uma falha persistente pararia todas as mensagens de um serviço sem ninguém ser avisado | — |

### Para o teste por serviço (decisão 3)

| Alternativa | Trade-off | Rever se |
| --- | --- | --- |
| **Disponibilidade pelo estado do pod ou pelo volume de requisições** | Não consumiria cota de Synthetics; mas a rota de saúde é excluída da instrumentação, o estado do pod não vê o gateway nem o NLB, e ausência de tráfego é o normal num ambiente de demonstração | Um sinal interno passar a atravessar o gateway |
| **Um teste só, no work-order** | Um quarto do consumo de cota, mas não diz qual serviço caiu | A cota de Synthetics apertar a ponto de espaçar as execuções (`synthetic_tick_every_seconds = 900`) não bastar |

## Consequências

- **Monitorar um serviço novo é acrescentar uma chave ao mapa**: o `plan` cria o dashboard, o teste sintético e
  os cinco monitores dele e acrescenta o serviço à Visão Geral, ao dashboard de Kubernetes e aos monitores da
  solução ([Infraestrutura](../terraform.md#serviço-novo-é-uma-chave-no-mapa)). Em troca, o serviço precisa
  seguir o padrão de nomes, e os quatro dividem os mesmos limiares até a calibração mostrar motivo para
  separá-los.
- **A contagem de recursos cresce com o número de serviços**: 10 dashboards e 33 monitores na conta. A conta
  de custom metrics também: `http.server.request.duration` passa a ter séries dos quatro serviços, sem tag
  nova indexada ([Observabilidade](../observability.md#5-custo-de-custom-metrics)).
- **Sem profundidade de fila**, uma fila parada sem nenhuma desistência não alerta. O que se vê é o consumo
  caindo no dashboard de Mensageria e, nas Sagas, iniciadas sem finalização.
- **Os monitores que cobrem os quatro serviços num só** (DLQ, outbox e cache) ficam sem tag de serviço, para não
  pintar de vermelho a linha de todos os serviços da Visão Geral quando um alerta
  ([Convenções](../conventions.md#tags-dos-recursos-criados)).
- **Os sinais dependem do código dos serviços.** Um evento renomeado num catálogo deixa o monitor verde sem
  medir nada; a revisão confere cada nome no catálogo de origem.
- **Os recursos antigos foram recriados**, com identificadores e URLs novos; links salvos para o dashboard de
  API e para os monitores antigos deixaram de funcionar.

## Referências

- [Monitores](../monitors.md) e [Dashboards](../dashboards.md): consultas, limiares e sobreposições.
- [ADR 0003](0003-uptime-por-verificacao-externa.md): verificação externa.
- [ADR 0005](0005-conjunto-minimo-de-alertas.md): critério de cada alerta e recusas.
- [Mapeamento de parâmetros do HTTP API do API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-parameter-mapping.html), para a reescrita de `/health/<contexto>` no gateway.
- [Data Streams Monitoring](https://docs.datadoghq.com/data_streams/) e a [integração AWS do Datadog](https://docs.datadoghq.com/integrations/amazon_web_services/), as alternativas recusadas.
