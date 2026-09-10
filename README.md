<div align="center">

# 🔭 Oficina Mecânica · Custom Monitoring

Este repositório é o dono de tudo o que **consome** a telemetria da Oficina Mecânica: dashboards, alertas e a verificação externa de disponibilidade.

![Terraform](https://img.shields.io/badge/Terraform-≥1.11-844FBA?logo=terraform&logoColor=white)
![Datadog](https://img.shields.io/badge/Datadog-provider%204.x-632CA6?logo=datadog&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-S3%20backend-FF9900?logo=amazonaws&logoColor=white)
![Dashboards](https://img.shields.io/badge/dashboards-4-632CA6)
![Monitores](https://img.shields.io/badge/monitores-9-632CA6)

[![CI](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/ci.yml/badge.svg)](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/ci.yml)
[![CD](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/cd.yml/badge.svg)](https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/actions/workflows/cd.yml)

</div>

## 📋 Sobre

Projeto acadêmico da pós-graduação em Arquitetura de Software da FIAP (turma 15SOAT),
parte do ecossistema da **Oficina Mecânica**.

A API e a Lambda da solução exportam logs, traces e métricas para o Datadog desde que a
coleta foi ligada: o serviço `oficina-mecanica-api` tem APM populado, a correlação
log ↔ trace funciona, e as quatro métricas de negócio respondem a consultas. E a conta
**não tinha um único dashboard, monitor, objetivo de nível de serviço ou teste
sintético**. O sinal chegava e parava ali.

O ADR 0005 da API declarou, com todas as letras, que uptime *"só se fecha com monitor
sintético externo, entrega da camada de coleta"* — e a camada de coleta não entregou.
Este repositório existe para fechar essa lacuna e **assumir essa dívida**.

## 🎯 Responsabilidade

**O que este repositório faz**

- Declara **quatro dashboards**: Visão Geral, API, Ordens de Serviço e Kubernetes.
- Declara **nove monitores acionáveis**, cobrindo disponibilidade externa, erros 5xx,
  latência p95, falhas no fluxo de negócio, memória e reinícios de pod, erros da Lambda,
  falha de envio de e-mail e degradação de dependência.
- Declara **um teste sintético** contra a rota pública `/api/health/ready`, alternado
  entre `live` e `paused` por uma variável de ambiente — porque o laboratório AWS Academy
  é ligado sob demanda e destruído ao final de cada sessão.
- Declara a **configuração de tags de métrica** de que os percentis dependem, que é
  simultaneamente pré-requisito do p95 e a alavanca de custo de custom metrics.

**O que ele não faz**

Não coleta nada, não altera instrumentação, agente ou extensão, não é dono do índice de
logs nem de políticas de retenção. **Ausências são documentadas, não simuladas**: o que a
coleta atual não produz aparece como limitação com causa, não como widget vazio.

**Uma propriedade que o define**

**Nenhuma consulta usa um nome que não tenha sido confirmado na conta.** Cada métrica,
tag e faceta citada foi verificada por uma consulta que devolveu dados — não por leitura
do código de origem. As divergências encontradas estão registradas, e a lista de
limitações tem a evidência de cada uma.

## 🧰 Stack

| Camada | Escolha | Por quê |
| --- | --- | --- |
| IaC | Terraform ≥ 1.11 | Mesmo piso de versão da solução; `templatestring` para a mensagem única |
| Provider | `DataDog/datadog` `>= 4.20.0, < 5.0.0` | HCL tipado, validado no `plan` — [ADR 0001](docs/adr/0001-terraform-com-provider-datadog.md) |
| State | S3 `bkt-oficina-mecanica`, trava nativa | Compartilhado com a solução — [ADR 0004](docs/adr/0004-state-no-s3-compartilhado.md) |
| Latência | métrica OTLP `http.server.request.duration` | Nome estável entre versões do agente — [ADR 0002](docs/adr/0002-latencia-por-metrica-otlp.md) |
| Disponibilidade | teste sintético externo | Única forma possível — [ADR 0003](docs/adr/0003-uptime-por-verificacao-externa.md) |
| Esteira | GitHub Actions | `Terraform Validation` + `Open Pull Request`; `plan`/`apply` com environment `production` |

Sem módulos, sem workspaces, sem diretório por ambiente: há um ambiente, e o reuso real
cabe em `locals`.

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
git clone https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring.git
cd oficina-mecanica-custom-monitoring/terraform

# verificação estrutural, sem credencial nenhuma
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

# prévia contra a conta real
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...
export TF_VAR_datadog_api_key=... TF_VAR_datadog_app_key=...
export TF_VAR_alert_emails='voce@exemplo.com'
export TF_VAR_environment_online=false

terraform init -reconfigure
terraform plan -lock=false
```

Passo a passo completo, incluindo como consultar a conta sem passar pelo Terraform e como
**não** aplicar sem querer, em [Como executar localmente](docs/local-setup.md).

## 🗂️ Estrutura

```
.
├── terraform/
│   ├── backend.tf                  state remoto no S3 compartilhado
│   ├── providers.tf                providers
│   ├── data.tf                     o state remoto do gateway
│   ├── variables.tf                entradas, incluindo os doze limiares
│   ├── locals.tf                   escopos, tags, links e a mensagem única
│   ├── outputs.tf                  endereços dos dashboards e identificadores
│   ├── metrics.tf                  configuração de tags e percentis
│   ├── synthetics.tf               verificação externa da rota pública
│   ├── dashboard_overview.tf       "a solução está de pé agora?"
│   ├── dashboard_api.tf            "onde está lenta e por quê?"
│   ├── dashboard_work_orders.tf    "o fluxo está andando?"
│   ├── dashboard_kubernetes.tf     "os pods têm folga?"
│   ├── monitors_api.tf             erros 5xx, latência p95
│   ├── monitors_work_orders.tf     falhas no fluxo de negócio
│   ├── monitors_kubernetes.tf      memória e reinícios de pod
│   ├── monitors_lambda.tf          erros de execução da Lambda
│   └── monitors_integrations.tf    envio de e-mail, dependência
├── docs/                           documentação e ADRs
└── .github/workflows/              ci.yml e cd.yml
```

## 📚 Documentação

| Documento | Conteúdo |
| --- | --- |
| 🔭 [Observabilidade](docs/observability.md) | **Documento âncora**: inventário dos sinais disponíveis com tags e semântica, as quinze limitações com evidência, as divergências e sua fonte de verdade, e a conta de custo de custom metrics |
| 📊 [Dashboards](docs/dashboards.md) | Um dashboard por seção com pergunta, público, janela, widgets e consultas — mais as sete regras visuais e os dashboards recusados |
| 🚨 [Monitores](docs/monitors.md) | Um monitor por seção com consulta, limiares, janela, agrupamento, prioridade e mensagem; os alertas recusados; a redundância assumida entre os dois monitores de erro; a calibração de limiar |
| 📐 [Convenções](docs/conventions.md) | Nomenclatura de dashboards, monitores, arquivos e recursos, e a estratégia de tagging reaproveitando as dimensões existentes |
| ☁️ [Infraestrutura](docs/terraform.md) | Providers, autenticação, state e trava, state remoto consumido, variáveis, locals, ausência de módulos, importação e prevenção de desvio |
| 🔁 [CI/CD](docs/ci-cd.md) | Os dois workflows job a job, o que reprova, o ruleset, o **inventário de configuração externa**, os passos manuais e as exposições aceitas |
| 📕 [Runbook](docs/runbook.md) | O que fazer quando cada monitor dispara, o ritual de subida e de derrubada do ambiente, e a calibração de limiares |
| 💻 [Como executar localmente](docs/local-setup.md) | Rodar `plan` local, consultar a conta por `curl`, e como não aplicar sem querer |
| 📐 [ADR 0001](docs/adr/0001-terraform-com-provider-datadog.md) | Terraform com o provider Datadog, em HCL tipado |
| 📐 [ADR 0002](docs/adr/0002-latencia-por-metrica-otlp.md) | Latência vem da métrica OTLP, não das *trace metrics* |
| 📐 [ADR 0003](docs/adr/0003-uptime-por-verificacao-externa.md) | Uptime por verificação externa, e a dívida do ADR 0005 da API |
| 📐 [ADR 0004](docs/adr/0004-state-no-s3-compartilhado.md) | State no S3 compartilhado, com o acoplamento declarado |
| 📐 [ADR 0005](docs/adr/0005-conjunto-minimo-de-alertas.md) | Conjunto mínimo de alertas para um ambiente efêmero |

Diagramas em [`docs/diagrams/`](docs/diagrams/): fluxo de integração contínua, fluxo de
entrega contínua e arquitetura de observabilidade.

## 🧩 Ecossistema

| Repositório | Papel | Relação com este repositório |
| --- | --- | --- |
| `oficina-mecanica-app` | API principal (NestJS) e manifestos do cluster | **Origem** de métricas, traces e logs da API. Dono do agente Datadog e da instrumentação. Alterar o que é coletado é mudança lá, não aqui |
| `oficina-mecanica-lambda-customer-auth` | Autenticação de clientes | Origem das métricas *enhanced* e dos logs da função. O monitor de erros de execução a observa por `functionname` |
| `oficina-mecanica-gateway` | API Gateway | **Publica `api_endpoint`**, que o teste sintético verifica. Este repositório lê o output do state dele |
| `oficina-mecanica-k8s` | Cluster EKS | Executa a API e o agente. Origem das métricas de contêiner, pod e nó |
| `oficina-mecanica-infra-base` | Rede | Dono do bucket que guarda o state de toda a solução |
| `oficina-mecanica-database` | Banco | Observado indiretamente, pelas métricas de cliente da API |
| **`oficina-mecanica-custom-monitoring`** | **Este repositório** | Consome a telemetria de todos os anteriores. Não produz sinal; produz leitura |

**A entrega deste repositório faz parte do ritual de subida do ambiente, depois da entrega
do gateway** — o endereço público muda a cada reprovisionamento. O ritual completo está no
[Runbook](docs/runbook.md).

## 📦 Estado

- Catorze recursos declarados: 1 configuração de tag de métrica, 4 dashboards, 8
  monitores e 1 teste sintético — que cria o nono monitor no destino.
- Toda consulta foi verificada contra a conta antes de virar código, e cada consulta de
  alerta passou por `POST /api/v1/monitor/validate`.
- A esteira valida `fmt`, `init`, `validate` e a chave de aplicação; a prévia contra a API
  do destino é a validação específica de Datadog, e ela rejeita consulta malformada, tag
  inexistente e widget inválido.
- Quinze limitações da coleta atual estão documentadas com evidência, e três eventos de
  log usados por monitores **nunca foram observados** — o que está registrado como tal, e
  não como "funcionando".

## 👥 Autores

- [Guilherme da Rocha Salvador](https://github.com/guilhermesalvador404)
- [Lucas Almeida da Silva](https://github.com/lucas-almeida-silva)
- [Ramoon Lincoln Barros Camacho](https://github.com/ramooncamacho)
- [Renan Santana Camacho](https://github.com/renancamacho)

## 📄 Licença

Projeto acadêmico (FIAP — 15SOAT), para fins educacionais. Sem licença aberta declarada
(`UNLICENSED`).
