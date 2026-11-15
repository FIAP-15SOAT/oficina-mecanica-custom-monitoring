<div align="center">

# 🔭 Oficina Mecânica · Custom Monitoring

Este repositório é o dono de tudo o que **consome** a telemetria da Oficina Mecânica: dashboards, alertas e a verificação externa de disponibilidade.

![Terraform](https://img.shields.io/badge/Terraform-≥1.11-844FBA?logo=terraform&logoColor=white)
![Datadog](https://img.shields.io/badge/Datadog-provider%204.x-632CA6?logo=datadog&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-S3%20backend-FF9900?logo=amazonaws&logoColor=white)
![Dashboards](https://img.shields.io/badge/dashboards-10-632CA6)
![Monitores](https://img.shields.io/badge/monitores-33-632CA6)

[![CI](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/ci.yml/badge.svg)](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/ci.yml)
[![CD](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/cd.yml/badge.svg)](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/cd.yml)

</div>

## 📋 Sobre

Projeto acadêmico da pós-graduação em Arquitetura de Software da FIAP (turma 15SOAT),
parte do ecossistema da **Oficina Mecânica**.

A solução tem quatro serviços NestJS — `work-order` (ordens de serviço, clientes e veículos),
`identity` (usuários e login), `billing` (orçamentos e cobranças) e `inventory` (serviços,
peças e estoque) — e duas funções Lambda: a `customer-auth` (login do cliente) e a
`notification` (envio de e-mail). Os serviços exportam métricas e traces por OTLP (o
protocolo do OpenTelemetry) e logs estruturados pela saída padrão (stdout) dos contêineres;
as Lambdas exportam métricas *enhanced* e logs pela extensão Datadog. Os serviços conversam
entre si por HTTP interno e por filas SQS, e uma aprovação de orçamento ou um pagamento
atravessa vários deles numa Saga, uma transação distribuída conduzida pelo work-order.

Este repositório consome esses sinais e declara dez dashboards, 33 monitores no total, um
teste sintético por serviço e a configuração de tags da métrica de latência. Os logs
instrumentados dos serviços incluem `trace_id` e `span_id` quando emitidos com um span
ativo; `request.id` identifica a requisição. Logs de bootstrap fora de spans e logs dos
componentes de plataforma não têm esse mesmo contrato de correlação.

## 🎯 Responsabilidade

**O que este repositório faz**

- Declara **dez dashboards**: Visão Geral, um por serviço (work-order, identity, billing e
  inventory), Ordens de Serviço, Kubernetes, Sagas, Pagamentos e Mensageria.
- Declara **33 monitores acionáveis**. Por serviço: disponibilidade externa, erros 5xx,
  latência p95, memória e reinícios de pod e health check degradado. Por Lambda: erros de
  execução. Da solução: falhas no fluxo de ordens de serviço, falha de envio de e-mail,
  mensagem na DLQ (a fila das mensagens que falharam), relay do outbox parado, webhook do
  Mercado Pago com assinatura inválida, compensações da aprovação de orçamento e falha na
  limpeza do cache.
- Declara **um teste sintético por serviço** contra a rota pública `/health/<contexto>`,
  alternado entre `live` e `paused` por uma variável de ambiente — porque o laboratório é
  ligado sob demanda e destruído ao final de cada sessão.
- Declara a **configuração de tags de métrica** de que os percentis dependem, que é
  simultaneamente pré-requisito do p95 e a alavanca de custo de custom metrics.

**O que ele não faz**

Não coleta nada, não altera instrumentação, agente ou extensão, não é dono do índice de
logs nem de políticas de retenção. **Ausências são documentadas, não simuladas**: o que a
coleta atual não produz aparece como limitação com causa, não como widget vazio.

**Uma propriedade que o define**

**Nenhuma consulta usa um nome sem fundamento verificável.** Métricas, tags e facetas seguem
o contrato vigente dos sinais; condições de falha permanecem identificadas mesmo quando não
possuem ocorrência recente. Uma consulta vazia, isoladamente, não comprova sucesso nem erro
de configuração.

## 🧰 Stack

| Camada | Escolha | Por quê |
| --- | --- | --- |
| IaC | Terraform ≥ 1.11 | Mesmo piso de versão da solução; `templatestring` para as mensagens de alerta |
| Provider | `DataDog/datadog` `>= 4.20.0, < 5.0.0` | HCL tipado, validado no `plan` — [ADR 0001](docs/adr/0001-terraform-com-provider-datadog.md) |
| State | S3 no bucket da variável de Actions da organização `TF_STATE_BUCKET`, trava nativa | Compartilhado com a solução — [ADR 0004](docs/adr/0004-state-no-s3-compartilhado.md) |
| Latência | métrica OTLP `http.server.request.duration` | Nome estável entre versões do agente — [ADR 0002](docs/adr/0002-latencia-por-metrica-otlp.md) |
| Disponibilidade | teste sintético externo, um por serviço | Única forma possível — [ADR 0003](docs/adr/0003-uptime-por-verificacao-externa.md) |
| Esteira | GitHub Actions | `Terraform Validation` + `Open Pull Request`; `plan`/`apply` com environment `production` |

Sem módulos, sem workspaces, sem diretório por ambiente: há um ambiente, e o reuso real
cabe em `locals`. Os serviços e as Lambdas monitorados são dois mapas em `locals.tf`, e o
que se repete por serviço é um `for_each` sobre eles: monitorar um serviço novo é acrescentar
uma chave ([Infraestrutura](docs/terraform.md#serviço-novo-é-uma-chave-no-mapa)).

## ⚙️ Pré-requisitos

- **Terraform ≥ 1.11.0**
- **Credenciais AWS do laboratório** — para o backend S3 e para ler o endereço público do
  state do gateway
- **Chave de API e chave de aplicação do Datadog** — a segunda de uma *service account*
  dedicada, com escopos mínimos

Sem credenciais AWS você ainda roda `fmt`, `init -backend=false` e `validate`, que é o que
pega a maior parte dos erros.

## 🚀 Início rápido

```bash
# baixar o repositório e entrar na pasta do Terraform
git clone https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring.git
cd oficina-mecanica-custom-monitoring/terraform

# conferir a formatação dos arquivos .tf, sem credencial nenhuma
terraform fmt -check -recursive
# instalar os providers sem conectar ao state remoto
terraform init -backend=false
# conferir sintaxe, tipos e referências
terraform validate

# credenciais AWS da sessão, para o state no S3 e o state do gateway
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...
# chaves de API e de aplicação do Datadog
export TF_VAR_datadog_api_key=... TF_VAR_datadog_app_key=...
# os seus próprios e-mails, nunca os do time
export TF_VAR_alert_emails='voce@exemplo.com'
# false mantém os testes sintéticos em paused na prévia
export TF_VAR_environment_online=false
# bucket do state compartilhado da solução, usado também para ler o state do gateway
export TF_STATE_BUCKET=<nome do bucket>
export TF_VAR_gateway_state_bucket="$TF_STATE_BUCKET"

# conectar ao state remoto no S3
terraform init -reconfigure -backend-config="bucket=$TF_STATE_BUCKET"
# prévia contra a conta real, sem travar o state da esteira
terraform plan -lock=false
```

Passo a passo completo, incluindo como consultar a conta sem passar pelo Terraform e como
**não** aplicar sem querer, em [Como executar localmente](docs/local-setup.md).

## 🗂️ Estrutura

```
.
├── terraform/
│   ├── .terraform.lock.hcl           versões e checksums dos providers
│   ├── backend.tf                  state remoto no S3 compartilhado
│   ├── providers.tf                providers
│   ├── data.tf                     o state remoto do gateway
│   ├── variables.tf                entradas, incluindo os dezoito limiares
│   ├── locals.tf                   mapas de serviços e de Lambdas, escopos, tags, links e mensagens
│   ├── outputs.tf                  endereços dos dashboards e identificadores
│   ├── metrics.tf                  configuração de tags e percentis
│   ├── synthetics.tf               verificação externa da rota de saúde de cada serviço
│   ├── dashboard_overview.tf       "a solução está de pé agora?"
│   ├── dashboard_service.tf        "onde o serviço está lento e por quê?" (um por serviço)
│   ├── dashboard_work_orders.tf    "o fluxo está andando?"
│   ├── dashboard_kubernetes.tf     "os pods têm folga?"
│   ├── dashboard_sagas.tf          "as transações distribuídas terminam?"
│   ├── dashboard_payments.tf       "as cobranças são criadas e resolvidas?"
│   ├── dashboard_messaging.tf      "as mensagens estão fluindo?"
│   ├── monitors_service.tf         erros 5xx, latência p95 (por serviço)
│   ├── monitors_work_orders.tf     falhas no fluxo de ordens de serviço
│   ├── monitors_kubernetes.tf      memória e reinícios de pod (por serviço)
│   ├── monitors_lambda.tf          erros de execução (por Lambda)
│   ├── monitors_integrations.tf    envio de e-mail, health check (por serviço)
│   ├── monitors_messaging.tf       mensagem na DLQ, relay do outbox parado
│   ├── monitors_payments.tf        webhook com assinatura inválida
│   ├── monitors_sagas.tf           compensações da aprovação de orçamento
│   ├── monitors_cache.tf           falha na limpeza do cache
│   ├── terraform.tfvars               configuração estável da stack
│   └── terraform.tfvars.example       referência para configuração local
├── docs/                           documentação e ADRs
├── .github/workflows/              ci.yml e cd.yml
├── .gitignore
└── README.md
```

## 📚 Documentação

| Documento | Conteúdo |
| --- | --- |
| 🔭 [Observabilidade](docs/observability.md) | **Documento âncora**: inventário dos sinais disponíveis com tags e semântica, as limitações atuais com evidência, as divergências e sua fonte de verdade, e a conta de custo de custom metrics |
| 📊 [Dashboards](docs/dashboards.md) | Um dashboard por seção com pergunta, público, janela, widgets e consultas — mais as nove regras visuais e os dashboards recusados |
| 🚨 [Monitores](docs/monitors.md) | Um monitor por seção com consulta, limiares, janela, agrupamento, prioridade e mensagem; os alertas recusados; as sobreposições assumidas entre monitores; a calibração de limiar |
| 📐 [Convenções](docs/conventions.md) | Nomenclatura de dashboards, monitores, arquivos e recursos, a estratégia de tagging reaproveitando as dimensões existentes e a tabela dos sinais de cada serviço com o catálogo de origem |
| ☁️ [Infraestrutura](docs/terraform.md) | Recursos provisionados, os mapas de serviços e de Lambdas, providers, autenticação, state e trava, state remoto consumido, variáveis, locals, ausência de módulos, importação e prevenção de desvio |
| 🔁 [CI/CD](docs/ci-cd.md) | Os dois workflows job a job, o que reprova, o ruleset, o **inventário de configuração externa**, os passos manuais e as exposições aceitas |
| 📕 [Runbook](docs/runbook.md) | O que fazer quando cada monitor dispara, o ritual de subida e de derrubada do ambiente, e a calibração de limiares |
| 💻 [Como executar localmente](docs/local-setup.md) | Rodar `plan` local, consultar a conta por `curl`, e como não aplicar sem querer |
| 📐 [ADR 0001](docs/adr/0001-terraform-com-provider-datadog.md) | Terraform com o provider Datadog, em HCL tipado |
| 📐 [ADR 0002](docs/adr/0002-latencia-por-metrica-otlp.md) | Latência vem da métrica OTLP, não das *trace metrics* |
| 📐 [ADR 0003](docs/adr/0003-uptime-por-verificacao-externa.md) | Uptime por verificação externa, um teste por serviço |
| 📐 [ADR 0004](docs/adr/0004-state-no-s3-compartilhado.md) | State no S3 compartilhado, com o acoplamento declarado |
| 📐 [ADR 0005](docs/adr/0005-conjunto-minimo-de-alertas.md) | Conjunto mínimo de alertas para um ambiente efêmero |
| 📐 [ADR 0006](docs/adr/0006-monitoramento-por-servico.md) | Monitoramento por serviço e da solução distribuída |

Diagramas em [`docs/diagrams/`](docs/diagrams/): fluxo de integração contínua, fluxo de
entrega contínua e arquitetura de observabilidade.

## 🧩 Ecossistema

| Repositório | Papel | Relação com este repositório |
| --- | --- | --- |
| `oficina-mecanica-work-order-service`, `oficina-mecanica-identity-service`, `oficina-mecanica-billing-service`, `oficina-mecanica-inventory-service` | Os quatro serviços (NestJS) | **Origem** de métricas, traces e logs de cada serviço, incluindo os sinais de Saga, cobrança, fila, outbox e cache. Alterar o que é coletado é mudança lá, não aqui |
| `oficina-mecanica-lambda-customer-auth`, `oficina-mecanica-lambda-notification` | Login do cliente e envio de e-mail | Origem das métricas *enhanced* e dos logs das funções. Os monitores de erros de execução as observam por `functionname`; o de falha de envio de e-mail lê o evento `notification.failed` da notification |
| `oficina-mecanica-api-gateway` | API Gateway | **Publica `api_endpoint`** e as rotas `/health/<contexto>`, que os testes sintéticos verificam. Este repositório lê o output do state dele |
| `oficina-mecanica-infra-k8s` | Cluster EKS | Executa os serviços e, no namespace `platform`, o Datadog Agent. Origem das métricas de contêiner, pod e nó |
| `oficina-mecanica-infra-messaging` | Tópico SNS e filas SQS FIFO | Observado indiretamente, pelo que os serviços registram ao consumir e publicar |
| `oficina-mecanica-infra-base` | Rede | Dono do bucket que guarda o state de toda a solução |
| `oficina-mecanica-infra-database-work-order`, `-identity`, `-billing` e `-inventory` | Banco e cache de cada serviço | Observados indiretamente, pelas métricas de cliente de banco e pelos eventos de cache dos serviços |
| **`oficina-mecanica-custom-monitoring`** | **Este repositório** | Consome a telemetria de todos os anteriores. Não produz sinal; produz leitura |

**A entrega deste repositório faz parte do ritual de subida do ambiente, depois da entrega
do gateway** — o endereço público muda a cada reprovisionamento. O ritual completo está no
[Runbook](docs/runbook.md).

## 📦 Estado

- Quarenta e quatro recursos declarados: 1 configuração de tag de métrica, 10 dashboards,
  29 monitores e 4 testes sintéticos — cada teste cria o seu próprio monitor no destino, o
  que dá os 33 monitores da conta.
- Consultas de dashboards e alertas ficam declaradas no Terraform, junto dos filtros,
  agrupamentos e limiares.
- A esteira executa `fmt`, `init` e `validate` e exige a presença da chave de aplicação.
  Com credenciais AWS disponíveis, executa também o `plan` contra os providers; isso não
  substitui a verificação de ingestão ou de ocorrências dos eventos monitorados.
- As limitações e os contratos da coleta estão descritos em
  [Observabilidade](docs/observability.md). Eventos condicionais podem não ter ocorrências
  no intervalo selecionado; uma consulta vazia não valida o caminho de falha.

## 👥 Autores

- [Guilherme da Rocha Salvador](https://github.com/guilhermesalvador404)
- [Lucas Almeida da Silva](https://github.com/lucas-almeida-silva)
- [Ramoon Lincoln Barros Camacho](https://github.com/ramooncamacho)
- [Renan Santana Camacho](https://github.com/renancamacho)

## 📄 Licença

Projeto acadêmico (FIAP — 15SOAT), para fins educacionais. Sem licença aberta declarada
(`UNLICENSED`).

