# Dashboards

Dez dashboards, declarados em sete arquivos `terraform/dashboard_*.tf`: `dashboard_service.tf` gera um dashboard
para cada um dos quatro serviços da solução (work-order, identity, billing e inventory), e cada um dos outros
seis arquivos declara um dashboard. Este documento é a fonte única das consultas: nenhum outro documento as
repete.

| Dashboard | Pergunta | Janela | Arquivo |
| --- | --- | --- | --- |
| [Visão Geral](#oficina-mecânica--visão-geral) | A solução está de pé agora? | 4 h | `dashboard_overview.tf` |
| [Serviço work-order, identity, billing e inventory](#oficina-mecânica--serviço-contexto) | Onde o serviço está lento, e por quê? | 1 h | `dashboard_service.tf` |
| [Ordens de Serviço](#oficina-mecânica--ordens-de-serviço) | O fluxo de ordens de serviço está andando, e onde ele para? | 7 d | `dashboard_work_orders.tf` |
| [Kubernetes](#oficina-mecânica--kubernetes) | Os pods estão com folga de recurso, ou vão ser encerrados? | 4 h | `dashboard_kubernetes.tf` |
| [Sagas](#oficina-mecânica--sagas) | As transações distribuídas terminam? | 7 d | `dashboard_sagas.tf` |
| [Pagamentos](#oficina-mecânica--pagamentos) | As cobranças são criadas e resolvidas? | 7 d | `dashboard_payments.tf` |
| [Mensageria](#oficina-mecânica--mensageria) | As mensagens estão fluindo? | 4 h | `dashboard_messaging.tf` |

Os nomes dos sinais e o motivo de cada ausência estão em [Observabilidade](observability.md), citados aqui por
sigla (L1, L13…). Os monitores ligados a cada dashboard estão em [Monitores](monitors.md).

Nas consultas abaixo, `<serviço>` é o nome do serviço na telemetria (`oficina-mecanica-<contexto>-service`) e
`<4 serviços>` é a expressão `env:production AND (service:… OR service:… OR service:… OR service:…)` com os
quatro, montada em `local.services_scope`.

---

## Regras visuais, aplicadas a todos

1. **Nota de abertura declarando a pergunta.** O primeiro widget de cada dashboard é uma nota que diz, em uma
   frase, o que a página responde — e a janela padrão.
2. **Seções nomeadas.** Todo widget vive dentro de um grupo com título; nenhum widget solto além da nota.
3. **Título com unidade.** `Latência p95 (s)`, `Working set por pod contra o limite (bytes)`,
   `Estrangulamento de CPU por pod (% dos períodos)`. Um número sem unidade não é uma leitura.
4. **Uma dimensão de quebra por widget**, ou duas quando a segunda é o resultado: fila **e** resultado,
   destino **e** status, tipo de Saga **e** desfecho. Também cabem dimensões que só identificam o item da
   primeira: namespace **e** pod, fila **e** tipo da mensagem. Rota **ou** status, pod **ou** nó. Dois eixos
   independentes produzem um emaranhado que ninguém lê em incidente.
5. **Formatação condicional nos indicadores de erro e de saturação**, e só neles: `% de 5xx`, `p95`, `% do
   limite de memória`, `erros da Lambda`, `pods emitindo métrica`. Verde, amarelo e vermelho alinhados com os
   limiares dos monitores, para que o dashboard e o alerta contem a mesma história.
6. **`live_span` explícito em todo widget.** Herdar a janela da página torna a leitura dependente de onde a
   pessoa clicou por último.
7. **Nenhum widget vazio sem nota.** Onde a ausência de dado é estrutural, uma nota amarela ao lado explica
   qual limitação a causa. A exceção declarada é o grupo Fila do dashboard do identity, descrita na seção do
   dashboard de serviço.
8. **A forma de fórmula é a padrão; `q = "..."` só onde não há legenda.** Na forma curta, o **nome da série
   na legenda é a própria consulta** — `avg:nodejs.eventloop.utilization{env:production,service:…}` no lugar
   de `utilização`. A forma de fórmula permite `alias`, e é ela que produz legenda legível.

   Duas regras derivadas, e a segunda é fácil de errar:

   - **Série sem agrupamento → `alias`.** É o rótulo que aparece na legenda.
   - **Série agrupada por tag → sem `alias`.** Um alias numa consulta com `by {…}` rotula **todas** as séries
     com o mesmo texto, e a distinção por pod, por rota ou por status desaparece da legenda. Sem alias, o
     destino nomeia cada série pelo valor do grupo.

   A exceção é `query_table`: ali o `alias` nomeia a **coluna**, e as linhas é que são os grupos — alias em
   consulta agrupada é o comportamento correto.

9. **Todo widget que soma declara `aggregator = "sum"`.** Um `toplist` ou um `query_value` reduzem a série
   temporal a um número, e **o padrão dessa redução é a média**. Num widget que promete "requisições na
   janela" ou "ordens que saíram de cada status", a média por intervalo é a leitura errada — e ela aparece
   como número quebrado (`1,5 ordens`), que é o sintoma que denuncia o problema. A forma curta `q = "..."`
   **não** permite escolher o redutor; a forma de fórmula, sim.

### Sobre `interval in progress`

A última barra de qualquer gráfico de barras sobre janela viva é **sempre parcial**: o intervalo corrente
ainda está enchendo, e o destino a rotula `interval in progress`. Não é defeito nem número errado — é o balde
aberto, e some sozinho quando o intervalo fecha.

Fixar um `rollup(sum, 86400)` **piora** isso, porque prende o balde a um dia inteiro: numa janela de 4 horas o
balde do dia corrente aparece com o total parcial do dia, e quem olha lê como se fosse o dia fechado. Por isso
nenhum widget de volume fixa `rollup`. Onde o total precisa ser inequívoco, o widget é um **indicador**, não
uma barra.

### Links entre dashboards

Os links vão num sentido só: a Visão Geral aponta para todos os dashboards de detalhe, e o de Sagas aponta para
Ordens de Serviço, Pagamentos e Mensageria. Nenhum aponta de volta, porque o endereço de um dashboard só
existe depois que ele é criado, e dois dashboards que se citam formam um ciclo que o Terraform recusa.

---

## `Oficina Mecânica · Visão Geral`

**Pergunta**: *a solução está de pé agora?* · **Janela**: 4 h · **Público**: todo o time
**Arquivo**: `terraform/dashboard_overview.tf`

Página de entrada. Uma linha por serviço e por Lambda, legível em segundos. Toda investigação sai daqui pelos
links da nota de abertura: um para o dashboard de cada serviço e um para cada dashboard de detalhe (Ordens de
Serviço, Sagas, Pagamentos, Mensageria e Kubernetes).

### Disponibilidade

| Widget | Consulta | Monitor ligado |
| --- | --- | --- |
| Monitores da solução | `manage_status` com `tag:(project:oficina-mecanica)` | todos |

O `manage_status` é o único widget que responde "o que está vermelho agora?" sem que a pessoa saiba de antemão
o que procurar. É nele que aparecem os monitores sem tag de serviço — mensagem na DLQ, relay do outbox parado
e falha na limpeza do cache ([Convenções](conventions.md#tags-dos-recursos-criados)).

### Serviço `<contexto>` — um grupo por serviço

Os quatro grupos (`Serviço billing`, `Serviço identity`, `Serviço inventory`, `Serviço work-order`) saem do mapa
de serviços, na ordem alfabética das chaves.

| Widget | Consulta | Monitor ligado |
| --- | --- | --- |
| Verificação externa de `/health/<contexto>` — histórico | `alert_graph` sobre o monitor do teste sintético do serviço | Disponibilidade externa do serviço |
| Monitores do serviço | `manage_status` com `tag:(service:<serviço>)`, só as contagens por estado | os do serviço |
| Requisições por minuto | `count:http.server.request.duration{env:production,service:<serviço>}.as_count().rollup(sum, 60)` | — |
| Respostas 5xx (% do total) | `(count:…{…,http.response.status_code:5*}.as_count() / count:…{…}.as_count()) * 100` — verde ≤ 1 %, amarelo > 1 %, vermelho > 5 % | — |
| Latência p95 (s) | `p95:http.server.request.duration{env:production,service:<serviço>}` — cores nos limiares do monitor de latência | Latência p95 do serviço |

### Negócio

| Widget | Consulta |
| --- | --- |
| Ordens de serviço criadas hoje | `sum:oficina.work_order.created{…work-order…}.as_count()`, janela de 1 d |
| Permanência média por status (s) | `avg:oficina.work_order.status.duration{…} by {oficina.work_order.status}` |
| Sagas finalizadas hoje por tipo e desfecho | `sum:oficina.saga.finished{…work-order…} by {oficina.saga.type,oficina.saga.outcome}.as_count()`, com `aggregator = "sum"` |

### Infra

| Widget | Consulta |
| --- | --- |
| Serviços com pods emitindo métrica | `count_nonzero(avg:kubernetes.memory.working_set{kube_namespace:work-order OR kube_namespace:identity OR …} by {kube_namespace})` — vermelho abaixo de 4, verde a partir de 4 |
| Memória sobre o limite por pod (%) | `(working_set / limits) * 100 by {kube_namespace,pod_name}` nos mesmos quatro namespaces — cores nos limiares do monitor de memória |

**O vermelho fica abaixo de quatro**, e não abaixo de um, porque a contagem é de namespaces com ao menos um pod
emitindo métrica: com um limite de um, um serviço inteiro fora do ar continuaria verde enquanto os outros três
emitissem métrica. A contagem não é por pod porque o autoescalonamento roda até dois pods por serviço, e os
pods a mais esconderiam um serviço sem nenhum.

`kubernetes.containers.running` **não** é usada: ela responde `pod_name:N/A` e não permite a contagem por pod.
E, por L1, esta contagem é de pods que **emitem métrica**, não de pods prontos.

### Lambda `<função>` — um grupo por Lambda

Dois grupos, `Lambda customer-auth` e `Lambda notification`, escopados por `functionname`.

| Widget | Consulta |
| --- | --- |
| Invocações na janela | `sum:aws.lambda.enhanced.invocations{functionname:<função>}.as_count()` |
| Erros de plataforma na janela | `sum:aws.lambda.enhanced.errors{…}.as_count()` — vermelho > 0 |
| Duração — média e máximo (s) | `avg:` e `max:aws.lambda.enhanced.duration{…}` |
| Partidas a frio (% das invocações) | `(invocations{…,cold_start:true} / invocations{…}) * 100` |

**Por que média e máximo, e não p95.** `p95:aws.lambda.enhanced.duration` responde `missing_aggregation`: a
métrica também é uma *distribution*. Habilitar percentis nela exigiria uma `datadog_metric_tag_configuration`
sobre uma métrica do namespace `aws.`, o que **descartaria as tags não listadas** — entre elas `cold_start`,
de que o widget ao lado depende. Média e máximo são gratuitos e respondem à mesma pergunta neste volume de
invocações. Gatilho para reavaliar: volume de invocações que torne a média enganosa.

---

## `Oficina Mecânica · Serviço <contexto>`

**Pergunta**: *onde o serviço está lento, e por quê?* · **Janela**: 1 h · **Público**: quem investiga
**Arquivo**: `terraform/dashboard_service.tf`, com `for_each` sobre o mapa de serviços · **Variáveis de
template**: `$env`, `$service` (o padrão é o serviço do dashboard)

São quatro, com o mesmo conteúdo: `Serviço work-order`, `Serviço identity`, `Serviço billing` e
`Serviço inventory`. A ordem dos grupos é deliberada e segue o caminho da requisição: entrada → dependência →
processo → evidência.

### Requisições

| Widget | Consulta |
| --- | --- |
| Requisições por classe de status (req/min) | três séries: `count:http.server.request.duration{$env,$service,http.response.status_code:2*}` (e `4*`, `5*`), `.as_count().rollup(sum, 60)` |
| Top 10 rotas por volume | `count:http.server.request.duration{$env,$service} by {http.route}.as_count()`, com `aggregator = "sum"` e `limit` de 10 |
| Rotas · volume, p50 (s), p95 (s) e % de 5xx | tabela com quatro consultas por `{http.route}` e a fórmula `errors / volume * 100` |

A tabela é o widget mais denso da página, e é onde uma investigação começa: as quatro leituras que decidem por
onde ir — quanto tráfego, quão lenta no caso típico, quão lenta na cauda, quanto dela falha.

**`http.route:N/A` aparece** nos widgets agrupados por rota: são requisições sem rota casada, tipicamente 404
de caminho inexistente. Não é defeito da consulta.

### Latência

| Widget | Consulta |
| --- | --- |
| Latência p50, p90, p95 e p99 (s) | quatro séries `pNN:http.server.request.duration{$env,$service}` + marcadores nos limiares do monitor de latência |
| Distribuição de latência na janela (s) | `avg:http.server.request.duration{$env,$service}` em widget de distribuição |
| Top 10 rotas por p95 (s) | `top(p95:http.server.request.duration{$env,$service} by {http.route}, 10, 'mean', 'desc')` |

Os marcadores desenham os dois limiares do monitor de latência sobre o gráfico: quem olha vê onde o alerta vai
disparar sem abrir a definição do monitor.

### Banco

| Widget | Consulta |
| --- | --- |
| Duração de operação no banco por operação — média e máximo (s) | `avg:db.client.operation.duration{$env,$service} by {db.operation.name}` e `max:…{$env,$service}` |
| Pool de conexões — usadas e ociosas contra o máximo | `avg:db.client.connection.count{$env,$service} by {db.client.connection.state}` e `avg:db.client.connection.max{$env,$service}` |
| Requisições aguardando conexão no pool | `avg:db.client.connection.pending_requests{$env,$service}` |

**Por que média e máximo, e não p95.** `db.client.operation.duration` também é uma *distribution*, e percentis
exigiriam uma segunda configuração de tags — que multiplicaria o custo de custom metrics sem que nenhum
monitor dependa dela. Uma nota amarela no próprio grupo diz isso. Gatilho para reavaliar: latência de banco
virar causa recorrente de latência alta no serviço.

A fila de espera por conexão é o sinal que **antecede** a saturação do pool: sobe antes de a latência do
serviço subir.

### Cache

| Widget | Consulta |
| --- | --- |
| Falhas de cache por evento | log `service:$service env:$env @oficina.event.name:(cache.unavailable OR cache.invalidation_failed)`, contagem por `@oficina.event.name`, em barras |

Cada serviço guarda leituras por id no próprio cache (Valkey, compatível com Redis). `cache.unavailable` é uma
leitura que caiu no banco porque o cache não respondeu, inclusive por tempo esgotado; `cache.invalidation_failed`
é uma chave que não foi apagada depois de uma escrita e fica com o valor antigo até expirar. Uma nota no grupo
diz isso.

**O grupo usa eventos de log, e não métrica**, porque a instrumentação do cliente de cache (`ioredis`) gera
span, não métrica: os eventos são o único sinal agregável que a aplicação emite sobre o cache.

### Chamadas de saída

| Widget | Consulta |
| --- | --- |
| Duração das chamadas HTTP de saída por destino — média e máximo (s) | `avg:` e `max:http.client.request.duration{$env,$service,!server.address:sqs.us-east-1.amazonaws.com,!server.address:sns.us-east-1.amazonaws.com,!server.address:datadog-agent.platform.svc.cluster.local,!server.address:169.254.169.254} by {server.address}` |
| Chamadas HTTP de saída por destino e status | `count:http.client.request.duration{…mesmo escopo…} by {server.address,http.response.status_code}.as_count()`, em barras |

`server.address` é o host chamado: outro serviço da solução, pela rota interna, ou o Mercado Pago, no billing.
As chamadas que o SDK da AWS faz à fila SQS e ao tópico SNS também entram na métrica e ficam de fora do grupo:
a leitura da fila espera até 20 s por mensagem (*long polling*) e achataria no zero as outras linhas do
gráfico. Ficam de fora também o envio de telemetria ao Datadog Agent (`datadog-agent.platform.svc.cluster.local`,
o exportador OTLP do próprio serviço) e a leitura de credenciais no serviço de metadados da instância EC2
(`169.254.169.254`), que não são chamadas do negócio. O consumo e o outbox estão no grupo Fila e no dashboard de Mensageria. Um serviço que não chama
ninguém deixa o grupo vazio.

### Fila

| Widget | Consulta |
| --- | --- |
| Mensagens consumidas por fila e resultado | `sum:oficina.messaging.consumed{$env,$service} by {messaging.destination.name,outcome}.as_count()`, em barras |

`outcome` é `success` (processada), `retry` (devolvida à fila para nova tentativa) ou `dead_lettered`
(desistida, vai para a DLQ, a fila das mensagens que falharam 5 vezes).

**No dashboard do identity este grupo fica sempre vazio**: o identity não consome fila. O conteúdo é o mesmo
nos dashboards dos quatro serviços, porque eles saem de um só bloco com `for_each`; uma nota só no identity exigiria um
conteúdo diferente por serviço para explicar um único widget.

### Runtime

| Widget | Consulta |
| --- | --- |
| Atraso do event loop, p99 (s) | `avg:nodejs.eventloop.delay.p99{$env,$service}` |
| Utilização do event loop (0 a 1) | `avg:nodejs.eventloop.utilization{$env,$service}` |
| Heap V8 — usado contra alocado (bytes) | `avg:v8js.memory.heap.used{$env,$service}` e `sum:v8js.memory.heap.space.size{$env,$service}` |

`v8js.memory.heap.limit` **não existe** na conta. O par de comparação é o tamanho alocado somado sobre os
espaços de heap.

### Erros

| Widget | Consulta |
| --- | --- |
| Logs de erro do serviço | `service:$service env:$env status:error`, colunas `@http.route`, `@http.response.status_code`, `@error.type`, `@oficina.error.message` |

Escopo por `service` **por inclusão**, nunca por exclusão: `klog` escreve em stderr e `status:error` sem escopo
traria `kube-proxy` e `metrics-server` como se fossem defeito da aplicação (L7).

---

## `Oficina Mecânica · Ordens de Serviço`

**Pergunta**: *o fluxo de ordens de serviço está andando, e onde ele para?* · **Janela**: 7 d
**Público**: operação e negócio · **Arquivo**: `terraform/dashboard_work_orders.tf`

Janela de 7 dias porque a unidade de análise é o ciclo de uma ordem de serviço, não a requisição. As métricas
vêm do work-order; as decisões de orçamento, do billing, que é o dono dos orçamentos.

**Média e máximo, não percentis.** As três métricas de negócio também são *distributions*, e p50/p95 sobre elas
exigiriam habilitar percentis métrica a métrica — o que dobra o custo em custom metrics de cada uma. Nenhum
monitor depende desses percentis, e para responder "alguma ordem ficou presa neste status?" o **máximo** é
mais direto que o p95. Percentis ficam habilitados apenas onde o monitor de latência depende deles:
`http.server.request.duration`.

| Grupo | Widget | Consulta |
| --- | --- | --- |
| Volume | Ordens de serviço criadas na janela | `sum:oficina.work_order.created{$env,$service}.as_count()`, indicador com `aggregator = "sum"` |
| Volume | Ordens de serviço criadas ao longo da janela | mesma consulta, em barras, **sem `rollup` fixo** |
| Permanência | Média por status (s) | `avg:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}` |
| Permanência | Máxima por status (s) | `max:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}` |
| Ciclo completo | Lead time — média e máximo (s) | `avg:` e `max:oficina.work_order.lead_time.duration{$env,$service}` |
| Ciclo completo | Diagnóstico até conclusão — média e máximo (s) | `avg:` e `max:oficina.work_order.diagnosis_to_completion.duration{$env,$service}` |
| Funil e decisões | Ordens que saíram de cada status | `count:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}.as_count()`, com `aggregator = "sum"` |
| Funil e decisões | Decisões de orçamento no billing — aprovados contra recusados | log: `service:oficina-mecanica-billing-service env:$env @oficina.event.name:(quote.approved OR quote.rejected)`, contagem por `@oficina.event.name` |

### O funil vem da métrica, não do log

`oficina.work_order.status.duration` é emitida **quando a ordem sai de um status**. Logo, `count:` dela por
status responde quantas ordens avançaram de cada etapa — o funil, com todos os status de que se sai, inclusive
`awaiting_payment` (aguardando o pagamento da cobrança) e `rejected` (orçamento recusado, de onde a ordem volta
a aguardar aprovação).

**O evento `work_order.status.updated` não serve para isso**: ele só é emitido em **duas das transições**,
`RECEIVED → IN_DIAGNOSIS` e `COMPLETED → DELIVERED`. As demais são efeito de ações de domínio — submissão e
aprovação de orçamento, cobrança, conclusão de serviço — e emitem os seus próprios eventos. Um widget sobre ele
mostra dois status e passa a impressão de que os outros não aconteceram.

**O que a métrica não cobre**: `DELIVERED` e `CANCELLED` não aparecem, porque status terminal não emite
permanência — não se sai dele. Uma nota amarela no grupo diz isso.

O widget de **decisões de orçamento** continua sendo de log: `quote.approved` e `quote.rejected` não têm
métrica equivalente. Ele escopa pelo billing, e não pelo `$service` da página, porque é o billing que registra a
decisão.

### Por que o widget de volume não fixa `rollup`

Um `rollup(sum, 86400)` cria um balde diário que só fecha à meia-noite. Em qualquer janela que não termine ali
— e o seletor de tempo do dashboard permite qualquer uma — o último balde aparece parcial, e o destino o
rotula **`interval in progress`**. Quem olha vê um número que não é o do dia. Sem `rollup` fixo, o destino
escolhe o intervalo pela janela, a largura da barra acompanha a seleção e não existe balde aberto.

### As duas grafias na mesma página

Widgets de métrica exibem `in_diagnosis`; widgets de log exibem o enum de domínio. É L12, é inerente às duas
fontes, e não é corrigível aqui. Com o funil na métrica, resta um único widget de log nesta página — o de
decisões de orçamento, que agrupa por nome de evento e não por status.

### Decisões de orçamento sem ocorrências

O widget agrupa as decisões pelos eventos `quote.approved` e `quote.rejected` (L15). Se não houver uma
recusa no intervalo selecionado, não haverá barra de recusas — ausência de evento, não defeito da consulta.

---

## `Oficina Mecânica · Kubernetes`

**Pergunta**: *os pods dos serviços e da plataforma estão com folga de recurso, ou vão ser encerrados?* ·
**Janela**: 4 h · **Arquivo**: `terraform/dashboard_kubernetes.tf` · **Variável de template**:
`$kube_namespace`, com os cinco namespaces como valores e como padrão

Cada serviço roda no namespace com o nome do seu contexto (`work-order`, `identity`, `billing`, `inventory`);
o namespace `platform` tem o Datadog Agent e o MailHog (o servidor de e-mail de teste). O escopo dos widgets é
`kube_cluster_name:oficina-mecanica,$kube_namespace`, e os gráficos por pod separam as séries por
`kube_namespace` e `pod_name`. Escolher namespaces no filtro do topo restringe esses gráficos.

| Grupo | Widget | Consulta |
| --- | --- | --- |
| CPU | CPU por pod contra requests e limits (cores) | `avg:kubernetes.cpu.usage.total{<escopo>} by {kube_namespace,pod_name} / 1e9`, sobreposta a `cpu.requests` e `cpu.limits` |
| CPU | Estrangulamento por pod (% dos períodos) | `(cfs.throttled.periods / cfs.periods) * 100 by {kube_namespace,pod_name}` |
| Memória | Working set por pod contra o limite (bytes) | `avg:kubernetes.memory.working_set{<escopo>} by {kube_namespace,pod_name}` e `avg:kubernetes.memory.limits{…}` |
| Memória | Working set sobre o limite por pod (%) | a razão × 100, com marcadores nos limiares do monitor de memória |
| Ciclo de vida | Pods emitindo métrica · `<namespace>`, um indicador por namespace | `count_nonzero(avg:kubernetes.memory.working_set{kube_cluster_name:oficina-mecanica,kube_namespace:<namespace>} by {pod_name})` |
| Ciclo de vida | Reinícios de contêiner por pod | `max:kubernetes.containers.restarts{<escopo>} by {kube_namespace,pod_name}` |
| Nós do cluster | CPU em uso por nó (%) | `100 - avg:system.cpu.idle{kube_cluster_name:oficina-mecanica} by {host}` |
| Nós do cluster | Memória utilizável por nó (%) | `avg:system.mem.pct_usable{kube_cluster_name:oficina-mecanica} by {host}` |

**Os indicadores de pods por namespace e os gráficos dos nós não seguem o filtro**: cada indicador já fixa o
seu namespace, e métricas de nó não têm namespace. A nota de abertura diz isso.

**Por que uma variável de template, e não uma lista de namespaces com `OR` no escopo.** O destino recusa a
mistura de vírgula com `OR` no mesmo escopo, e uma variável dentro de uma expressão com `OR` não é uma forma
documentada. Com vários valores padrão, o próprio destino une os namespaces com `OR`, e o escopo fica só com
vírgulas. Listar os cinco como padrão, em vez de `*`, mantém `kube-system` e os demais namespaces do cluster
fora da visão padrão.

**Memória é `working_set`, não `usage`**, porque `working_set` é o que o encerramento por falta de memória
observa.

**A divisão por `1e9`** é obrigatória: uso vem em nanocores, `requests` e `limits` em cores (L13). Sem ela a
sobreposição fica nove ordens de grandeza fora.

**Métricas de nó não têm dimensão de serviço.** O escopo possível é o cluster (`kube_cluster_name`), que
continua sendo inclusão explícita e não curinga.

**A nota de abertura explica L1** e aponta o dashboard pronto de **Kubernetes** do próprio destino
(`Dashboards → Kubernetes`), alimentado pela mesma coleta do *kubelet*, para a visão de plataforma que este
dashboard não cobre.

---

## `Oficina Mecânica · Sagas`

**Pergunta**: *as transações distribuídas terminam?* · **Janela**: 7 d · **Público**: quem investiga uma ordem
de serviço parada · **Arquivo**: `terraform/dashboard_sagas.tf`

Uma Saga é uma transação que atravessa vários serviços, conduzida pelo work-order: cada passo é um comando
enviado por fila a outro serviço, e se um passo falha os anteriores são desfeitos (a Saga é **compensada**).
Há dois tipos: `QUOTE_APPROVAL`, a aprovação de orçamento (o billing aprova, o inventory reserva as peças e o
work-order muda a ordem de serviço), e `PAYMENT`, a cobrança da ordem de serviço no Mercado Pago. Todos os
sinais vêm do work-order.

A nota de abertura liga ao funil de Ordens de Serviço, a Mensageria e ao item de mensagem na DLQ do
[Runbook](runbook.md#mensagem-na-dlq).

| Grupo | Widget | Consulta |
| --- | --- | --- |
| Iniciadas e finalizadas | Sagas iniciadas por tipo | `sum:oficina.saga.started{…work-order…} by {oficina.saga.type}.as_count()`, em barras |
| Iniciadas e finalizadas | Sagas finalizadas por tipo e resultado | `sum:oficina.saga.finished{…work-order…} by {oficina.saga.type,oficina.saga.outcome}.as_count()`, em barras |
| Sem finalização e compensação | Sagas por tipo · iniciadas sem finalização e % compensadas na janela | tabela por `oficina.saga.type` com `iniciadas - finalizadas` e `compensadas / finalizadas * 100` |
| Duração | Duração das Sagas por tipo — média e máximo (s) | `avg:` e `max:oficina.saga.duration{…work-order…} by {oficina.saga.type}` |
| Compensações por motivo | Sagas compensadas por tipo e motivo na janela | log `service:<work-order> env:production @oficina.event.name:saga.compensated`, contagem por `@oficina.saga.type` e `@oficina.saga.failure_reason` |

`oficina.saga.outcome` é `completed` (todos os passos feitos) ou `compensated` (desfeita).

### Como ler "iniciadas sem finalização"

Uma nota ao lado da tabela separa os dois tipos, porque a mesma diferença quer dizer coisas diferentes:

- **Em `QUOTE_APPROVAL`, que termina em segundos, diferença positiva é Saga parada**: uma mensagem está presa,
  e o próximo passo é o dashboard de Mensageria e o item de DLQ do runbook.
- **A Saga `PAYMENT` fica aberta enquanto a cobrança aguarda o pagamento do cliente**, até a cobrança expirar.
  Diferença nela só é Saga parada se a cobrança já aparece resolvida no dashboard de Pagamentos.

A taxa de compensação fica aqui, e não num monitor: com o volume deste ambiente, uma taxa dispara com uma
única amostra. O monitor conta compensações de `QUOTE_APPROVAL` em número absoluto
([Monitores](monitors.md#sagas--compensações-da-aprovação-de-orçamento)).

**Média e máximo, não percentis**, pelo mesmo motivo do dashboard de Ordens de Serviço: percentis de
`oficina.saga.duration` exigiriam uma configuração de tags e multiplicariam o custo sem uma pergunta que a
média e o máximo não respondam com este volume.

---

## `Oficina Mecânica · Pagamentos`

**Pergunta**: *as cobranças são criadas e resolvidas?* · **Janela**: 7 d · **Público**: operação e negócio ·
**Arquivo**: `terraform/dashboard_payments.tf`

O billing cria a cobrança de uma ordem de serviço no Mercado Pago, o provedor de pagamento, e recebe o
resultado por uma notificação HTTP assinada (webhook). Todos os sinais vêm do billing.

| Grupo | Widget | Consulta |
| --- | --- | --- |
| Cobranças | Cobranças criadas na janela | `sum:oficina.payment.requested{…billing…}.as_count()`, indicador |
| Cobranças | Cobranças resolvidas por status | `sum:oficina.payment.resolved{…billing…} by {oficina.payment.status}.as_count()`, em barras |
| Cobranças | Cobranças resolvidas por status na janela | a mesma consulta em toplist, com `aggregator = "sum"` |
| Webhooks | Webhooks do Mercado Pago recebidos por resultado da assinatura | `sum:oficina.payment.webhook.received{…billing…} by {outcome}.as_count()`, em barras |
| Mercado Pago | Duração das chamadas do billing ao Mercado Pago — média e máximo (s) | `avg:` e `max:http.client.request.duration{…billing…,server.address:api.mercadopago.com}` |
| Mercado Pago | Chamadas do billing ao Mercado Pago por status | `count:http.client.request.duration{…,server.address:api.mercadopago.com} by {http.response.status_code}.as_count()`, em barras |

`oficina.payment.status` é `APPROVED`, `REJECTED` (cartão recusado), `EXPIRED` (o cliente não pagou no prazo)
ou `CANCELLED`. Os três últimos são desfechos normais do pagamento e ficam aqui, sem monitor
([ADR 0005](adr/0005-conjunto-minimo-de-alertas.md)). No webhook, `outcome` é `valid` ou `invalid_signature`;
recusas acima do limiar disparam o monitor de webhook com assinatura inválida.

---

## `Oficina Mecânica · Mensageria`

**Pergunta**: *as mensagens estão fluindo?* · **Janela**: 4 h · **Público**: quem investiga uma Saga parada ·
**Arquivo**: `terraform/dashboard_messaging.tf`

Os serviços trocam comandos e eventos por um tópico SNS (`oficina-events.fifo`) e por filas SQS FIFO, que
entregam na ordem de envio, uma por consumidor: `work-order.fifo`, `billing.fifo`, `inventory.fifo` e
`notification.fifo`, da Lambda notification. Cada serviço grava a mensagem que vai publicar numa tabela
`outbox` do próprio banco e um laço do serviço (o relay) a publica no tópico.

**Sem profundidade de fila nem idade da mensagem mais antiga.** São métricas do SQS que exigem a integração AWS
do Datadog, indisponível no laboratório (L2). A nota de abertura diz isso; os gráficos usam o que as
aplicações registram.

| Grupo | Widget | Consulta |
| --- | --- | --- |
| Consumo | Mensagens consumidas por fila e resultado | `sum:oficina.messaging.consumed{<4 serviços>} by {messaging.destination.name,outcome}.as_count()`, em barras |
| Consumo | Mensagens consumidas por fila e resultado na janela | a mesma consulta em toplist, com `aggregator = "sum"` |
| Fila da Lambda notification | E-mails da fila notification.fifo por resultado | log `service:oficina-mecanica-lambda-notification env:production @oficina.event.name:(notification.sent OR notification.failed)`, contagem por `@oficina.notification.outcome`, em barras |
| DLQ | Mensagens enviadas à DLQ por serviço, fila e tipo na janela | log `<4 serviços> @oficina.event.name:messaging.message.dead_lettered`, toplist por `service`, `@messaging.destination.name` e `@oficina.messaging.message.type` |
| Outbox | Falhas de publicação do outbox por serviço | log `<4 serviços> @oficina.event.name:messaging.outbox.publish_failed`, contagem por `service`, em barras |

Na Lambda notification, `@oficina.notification.outcome` é `sent`, `retry` (a mensagem volta à fila) ou
`dead_lettered` (última tentativa, a mensagem vai para a DLQ).

O identity não consome fila e só aparece no grupo Outbox, porque também publica eventos.

---

## Dashboards recusados

| Recusado | Motivo |
| --- | --- |
| **Um dashboard de serviço único, com seletor de serviço** | A Visão Geral, o resumo da entrega e a mensagem de cada alerta não conseguiriam apontar para o serviço degradado: o link abriria o serviço padrão do seletor. Um dashboard por serviço, gerado do mesmo bloco, custa o mesmo código — ver [ADR 0006](adr/0006-monitoramento-por-servico.md) |
| **Lambda dedicado** | Quatro métricas por função, e nenhum trace na customer-auth (L4). Duplicaria os grupos de Lambda da Visão Geral sem acrescentar leitura |
| **Saúde / Disponibilidade dedicado** | A página de cada teste sintético no destino entrega mais: histórico por localidade, tempos por fase da requisição e corpo da resposta |
| **Erros / Troubleshooting dedicado** | Responde a mesma pergunta que o dashboard de serviço responde melhor, com banco, cache e event loop ao lado — que é onde a causa costuma estar |
| **Integrações dedicado** | As chamadas de saída de cada serviço já estão no dashboard dele, e as do Mercado Pago no de Pagamentos |
| **Por pessoa ou por time** | Quatro pessoas. Um dashboard por pessoa é cerimônia |

---

## Como acrescentar um dashboard

1. Confirme que **cada nome de métrica, tag e faceta existe na conta** — uma consulta que devolve série com
   dados, não uma leitura do código. Um nome não confirmado é rejeitado na revisão.
2. Crie `terraform/dashboard_<area>.tf` com um único `datadog_dashboard`.
3. Nomeie como `Oficina Mecânica · <Área>` e aplique `tags = local.dashboard_tags` — ver
   [Convenções](conventions.md).
4. Aplique as nove regras visuais do topo deste documento.
5. Acrescente o output do endereço em `terraform/outputs.tf`, a linha no resumo do CD
   (`.github/workflows/cd.yml`) e o link na nota de abertura da Visão Geral, sem link de volta.
6. Documente aqui: pergunta, público, janela, widgets, consultas e monitores ligados.
7. Abra o Pull Request. O `terraform plan` do CI é a validação: ele rejeita consulta malformada, tag
   inexistente e widget inválido.

Para um serviço novo, não crie dashboard: acrescente a chave ao mapa de serviços
([Infraestrutura](terraform.md#serviço-novo-é-uma-chave-no-mapa)).
