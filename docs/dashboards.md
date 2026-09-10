# Dashboards

Quatro dashboards, um arquivo Terraform cada, em `terraform/dashboard_*.tf`. Este documento é a fonte única
das consultas: nenhum outro documento as repete.

Os nomes dos sinais e o motivo de cada ausência estão em [Observabilidade](observability.md), citados aqui por
sigla (L1, L13…). Os monitores ligados a cada dashboard estão em [Monitores](monitors.md).

---

## Regras visuais, aplicadas aos quatro

1. **Nota de abertura declarando a pergunta.** O primeiro widget de cada dashboard é uma nota que diz, em uma
   frase, o que a página responde — e a janela padrão.
2. **Seções nomeadas.** Todo widget vive dentro de um grupo com título; nenhum widget solto além da nota.
3. **Título com unidade.** `Latência p95 (s)`, `Working set por pod contra o limite (bytes)`,
   `Estrangulamento de CPU por pod (% dos períodos)`. Um número sem unidade não é uma leitura.
4. **Uma dimensão de quebra por widget.** Rota **ou** status, pod **ou** nó. Dois eixos num gráfico produzem
   um emaranhado que ninguém lê em incidente.
5. **Formatação condicional nos indicadores de erro e de saturação**, e só neles: `% de 5xx`, `p95`, `% do
   limite de memória`, `erros da Lambda`, `pods emitindo métrica`. Verde, amarelo e vermelho alinhados com os
   limiares dos monitores, para que o dashboard e o alerta contem a mesma história.
6. **`live_span` explícito em todo widget.** Herdar a janela da página torna a leitura dependente de onde a
   pessoa clicou por último.
7. **Nenhum widget vazio sem nota.** Onde a ausência de dado é estrutural, uma nota amarela ao lado explica
   qual limitação a causa.

---

## `Oficina Mecânica · Visão Geral`

**Pergunta**: *a solução está de pé agora?* · **Janela**: 4 h · **Público**: todo o time
**Arquivo**: `terraform/dashboard_overview.tf`

Página de entrada. Um número por área, sem quebra por dimensão, legível em segundos. Toda investigação sai
daqui por um dos três links da nota de abertura.

### Disponibilidade

| Widget | Consulta | Monitor ligado |
| --- | --- | --- |
| Verificação externa da rota pública — histórico | `alert_graph` sobre o monitor do teste sintético | Disponibilidade externa |
| Monitores da solução | `manage_status` com `tag:(project:oficina-mecanica)` | todos |

O `manage_status` é o único widget que responde "o que está vermelho agora?" sem que a pessoa saiba de antemão
o que procurar.

### API

| Widget | Consulta |
| --- | --- |
| Requisições por minuto | `count:http.server.request.duration{env:production,service:oficina-mecanica-api}.as_count().rollup(sum, 60)` |
| Respostas 5xx (% do total) | `(count:…{…,http.response.status_code:5*}.as_count() / count:…{…}.as_count()) * 100` — verde ≤ 1 %, amarelo > 1 %, vermelho > 5 % |
| Latência p95 (s) | `p95:http.server.request.duration{env:production,service:oficina-mecanica-api}` — cores nos limiares do monitor de latência |

### Negócio

| Widget | Consulta |
| --- | --- |
| Ordens de serviço criadas hoje | `sum:oficina.work_order.created{…}.as_count()`, janela de 1 d |
| Permanência média por status (s) | `avg:oficina.work_order.status.duration{…} by {oficina.work_order.status}` |

### Infra

| Widget | Consulta |
| --- | --- |
| Pods da API emitindo métrica | `count_nonzero(avg:kubernetes.memory.working_set{kube_deployment:oficina-api} by {pod_name})` |
| Memória sobre o limite por pod (%) | `(working_set / limits) * 100 by {pod_name}` — cores nos limiares do monitor de memória |

`kubernetes.containers.running` **não** é usada: ela responde `pod_name:N/A` e não permite a contagem por pod.
E, por L1, esta contagem é de pods que **emitem métrica**, não de pods prontos.

### Lambda customer-auth

| Widget | Consulta |
| --- | --- |
| Invocações na janela | `sum:aws.lambda.enhanced.invocations{functionname:lbd-oficina-mecanica-customer-auth}.as_count()` |
| Erros de plataforma na janela | `sum:aws.lambda.enhanced.errors{…}.as_count()` — vermelho > 0 |
| Duração — média e máximo (s) | `avg:` e `max:aws.lambda.enhanced.duration{…}` |
| Partidas a frio (% das invocações) | `(invocations{…,cold_start:true} / invocations{…}) * 100` |

**Por que média e máximo, e não p95.** `p95:aws.lambda.enhanced.duration` responde `missing_aggregation`: a
métrica também é uma *distribution*. Habilitar percentis nela exigiria uma `datadog_metric_tag_configuration`
sobre uma métrica do namespace `aws.`, o que **descartaria as tags não listadas** — entre elas `cold_start`,
de que o widget ao lado depende. Média e máximo são gratuitos e respondem à mesma pergunta neste volume de
invocações. Gatilho para reavaliar: volume de invocações que torne a média enganosa.

O grupo escopa por `functionname` e **não** por `env`, por L8.

---

## `Oficina Mecânica · API`

**Pergunta**: *onde a API está lenta, e por quê?* · **Janela**: 1 h · **Público**: quem investiga
**Arquivo**: `terraform/dashboard_api.tf` · **Variáveis de template**: `$env`, `$service`

A ordem dos grupos é deliberada e segue o caminho da requisição: entrada → dependência → processo → evidência.

### Requisições

| Widget | Consulta |
| --- | --- |
| Requisições por classe de status (req/min) | três séries: `count:http.server.request.duration{$env,$service,http.response.status_code:2*}` (e `4*`, `5*`), `.as_count().rollup(sum, 60)` |
| Top 10 rotas por volume | `top(count:http.server.request.duration{$env,$service} by {http.route}.as_count(), 10, 'sum', 'desc')` |
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

Os marcadores desenham os dois limiares do monitor de latência sobre o gráfico: quem olha vê onde o alerta vai disparar sem
abrir a definição do monitor.

### Banco

| Widget | Consulta |
| --- | --- |
| Duração de operação no banco por operação — média e máximo (s) | `avg:db.client.operation.duration{$env,$service} by {db.operation.name}` e `max:…{$env,$service}` |
| Pool de conexões — usadas e ociosas contra o máximo | `avg:db.client.connection.count{$env,$service} by {db.client.connection.state}` e `avg:db.client.connection.max{$env,$service}` |
| Requisições aguardando conexão no pool | `avg:db.client.connection.pending_requests{$env,$service}` |

**Por que média e máximo, e não p95.** `db.client.operation.duration` também é uma *distribution*, e percentis
exigiriam uma segunda configuração de tags — que multiplicaria o custo de custom metrics sem que nenhum
monitor dependa dela. Uma nota amarela no próprio grupo diz isso. Gatilho para reavaliar: latência de banco
virar causa recorrente de latência alta na API.

A fila de espera por conexão é o sinal que **antecede** a saturação do pool: sobe antes de a latência da API
subir.

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
| Logs de erro da API | `service:$service env:$env status:error`, colunas `@http.route`, `@http.response.status_code`, `@error.type`, `@oficina.error.message` |

Escopo por `service` **por inclusão**, nunca por exclusão: `klog` escreve em stderr e `status:error` sem escopo
traria `kube-proxy` e `metrics-server` como se fossem defeito da aplicação (L7).

---

## `Oficina Mecânica · Ordens de Serviço`

**Pergunta**: *o fluxo de ordens de serviço está andando, e onde ele para?* · **Janela**: 7 d
**Público**: operação e negócio · **Arquivo**: `terraform/dashboard_work_orders.tf`

Janela de 7 dias porque a unidade de análise é o ciclo de uma ordem de serviço, não a requisição.

**Média e máximo, não percentis.** As três métricas de negócio também são *distributions*, e p50/p95 sobre elas
exigiriam habilitar percentis metrica a metrica — o que dobra o custo em custom metrics de cada uma. Nenhum
monitor depende desses percentis, e para responder "alguma ordem ficou presa neste status?" o **máximo** é
mais direto que o p95. Percentis ficam habilitados apenas onde o monitor de latência depende deles:
`http.server.request.duration`.

| Grupo | Widget | Consulta |
| --- | --- | --- |
| Volume | Ordens de serviço criadas | `sum:oficina.work_order.created{$env,$service}.as_count()`, em barras, **sem `rollup` fixo** |
| Permanência | Média por status (s) | `avg:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}` |
| Permanência | Máxima por status (s) | `max:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}` |
| Ciclo completo | Lead time — média e máximo (s) | `avg:` e `max:oficina.work_order.lead_time.duration{$env,$service}` |
| Ciclo completo | Diagnóstico até conclusão — média e máximo (s) | `avg:` e `max:oficina.work_order.diagnosis_to_completion.duration{$env,$service}` |
| Funil | Ordens que saíram de cada status | `count:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}.as_count()` |
| Funil | Decisões de orçamento | log: `@oficina.event.name:(quote.approved OR quote.rejected)`, contagem por `@oficina.event.name` |

### O funil vem da métrica, e a razão mudou

O desenho original supunha que **nenhuma métrica** responderia "quantas ordens passaram por cada status", e
por isso o funil nasceu como widget de log sobre `work_order.status.updated`. **A verificação em produção
mostrou que a suposição estava errada, nas duas pontas:**

- `oficina.work_order.status.duration` é emitida **quando a ordem sai de um status**. Logo,
  `count:` dela por status responde exatamente quantas ordens avançaram de cada etapa — o funil, com os seis
  status.
- O evento `work_order.status.updated` **não** cobre o fluxo: ele só é emitido em **duas das transições**,
  `RECEIVED → IN_DIAGNOSIS` e `COMPLETED → DELIVERED`. As demais são efeito de ações de domínio — submissão e
  aprovação de orçamento, conclusão de serviço — e emitem os seus próprios eventos. Um widget sobre ele
  mostrava dois status e dava a impressão de que os outros quatro não tinham acontecido.

O funil passou para a métrica. **O que ela não cobre**: `DELIVERED` e `CANCELLED` não aparecem, porque status
terminal não emite permanência — não se sai dele. Uma nota amarela no grupo diz isso.

O widget de **decisões de orçamento** continua sendo de log: `quote.approved` e `quote.rejected` não têm
métrica equivalente.

### Por que o widget de volume não fixa `rollup`

Um `rollup(sum, 86400)` cria um balde diário que só fecha à meia-noite. Em qualquer janela que não termine ali
— e o seletor de tempo do dashboard permite qualquer uma — o último balde aparece parcial, e o destino o
rotula **`interval in progress`**. Quem olha vê um número que não é o do dia. Sem `rollup` fixo, o destino
escolhe o intervalo pela janela, a largura da barra acompanha a seleção e não existe balde aberto.

### As duas grafias na mesma página

Widgets de métrica exibem `in_diagnosis`; widgets de log exibem o enum de domínio. É L12, é inerente às duas
fontes, e não é corrigível aqui. Com o funil migrado para a métrica, resta um único widget de log nesta
página — o de decisões de orçamento, que agrupa por nome de evento e não por status.

### `quote.rejected` nunca foi observado

Uma nota amarela no grupo de transições registra: em 30 dias há uma ocorrência de `quote.approved` e **zero**
de recusa (L15). O widget ficará com uma única barra até que uma recusa aconteça — ausência de evento, não
defeito da consulta.

---

## `Oficina Mecânica · Kubernetes`

**Pergunta**: *os pods da API estão com folga de recurso, ou vão ser encerrados?* · **Janela**: 4 h
**Arquivo**: `terraform/dashboard_kubernetes.tf`

| Grupo | Widget | Consulta |
| --- | --- | --- |
| CPU | CPU por pod contra requests e limits (cores) | `avg:kubernetes.cpu.usage.total{kube_deployment:oficina-api} by {pod_name} / 1e9`, sobreposta a `cpu.requests` e `cpu.limits` |
| CPU | Estrangulamento por pod (% dos períodos) | `(cfs.throttled.periods / cfs.periods) * 100 by {pod_name}` |
| Memória | Working set por pod contra o limite (bytes) | `avg:kubernetes.memory.working_set{…} by {pod_name}` e `avg:kubernetes.memory.limits{…} by {pod_name}` |
| Memória | Working set sobre o limite por pod (%) | a razão × 100, com marcadores nos limiares do monitor de memória |
| Ciclo de vida | Pods emitindo métrica | `count_nonzero(avg:kubernetes.memory.working_set{…} by {pod_name})` |
| Ciclo de vida | Reinícios de contêiner por pod | `max:kubernetes.containers.restarts{…} by {pod_name}` |
| Nós | CPU em uso por nó (%) | `100 - avg:system.cpu.idle{kube_cluster_name:oficina-mecanica} by {host}` |
| Nós | Memória utilizável por nó (%) | `avg:system.mem.pct_usable{kube_cluster_name:oficina-mecanica} by {host}` |

**Memória é `working_set`, não `usage`**, porque `working_set` é o que o encerramento por falta de memória
observa.

**A divisão por `1e9`** é obrigatória: uso vem em nanocores, `requests` e `limits` em cores (L13). Sem ela a
sobreposição fica sete ordens de grandeza fora.

**Métricas de nó não têm dimensão de serviço.** O escopo possível é o cluster (`kube_cluster_name`), que
continua sendo inclusão explícita e não curinga.

**A nota de abertura explica L1** e aponta o dashboard pronto de **Kubernetes** do próprio destino
(`Dashboards → Kubernetes`), alimentado pela mesma coleta do *kubelet*, para a visão de plataforma que este
dashboard não cobre.

---

## Dashboards recusados

| Recusado | Motivo |
| --- | --- |
| **Lambda dedicado** | Quatro métricas e nenhum trace (L4). Duplicaria o grupo Lambda da Visão Geral sem acrescentar leitura |
| **Saúde / Disponibilidade dedicado** | A página do próprio teste sintético no destino entrega mais: histórico por localidade, tempos por fase da requisição e corpo da resposta |
| **Erros / Troubleshooting dedicado** | Responde a mesma pergunta que o dashboard de API responde melhor, com banco e event loop ao lado — que é onde a causa costuma estar |
| **Integrações dedicado** | A única integração com catálogo de falha é o SMTP. São dois widgets, e eles cabem no dashboard de API |
| **Por pessoa ou por time** | Quatro pessoas. Um dashboard por pessoa é cerimônia |

---

## Como acrescentar um dashboard

1. Confirme que **cada nome de métrica, tag e faceta existe na conta** — uma consulta que devolve série com
   dados, não uma leitura do código. Um nome não confirmado é rejeitado na revisão.
2. Crie `terraform/dashboard_<area>.tf` com um único `datadog_dashboard`.
3. Nomeie como `Oficina Mecânica · <Área>` e aplique `tags = local.api_tags` — ver [Convenções](conventions.md).
4. Aplique as sete regras visuais do topo deste documento.
5. Acrescente o output do endereço em `terraform/outputs.tf` e o link na nota de abertura da Visão Geral.
6. Documente aqui: pergunta, público, janela, widgets, consultas e monitores ligados.
7. Abra o Pull Request. O `terraform plan` do CI é a validação: ele rejeita consulta malformada, tag
   inexistente e widget inválido.
