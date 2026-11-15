# Infraestrutura como código

Como a configuração do Datadog é declarada, versionada e reconciliada. A execução no seu computador está em
[Como executar localmente](local-setup.md); a execução na esteira, em [CI/CD](ci-cd.md).

---

## O que a stack provisiona

Quarenta e cinco recursos, todos na conta Datadog `us5`. **Nenhum recurso AWS é criado aqui.**

| Recurso | Quantidade | De onde vem a quantidade | Arquivo |
| --- | ---: | --- | --- |
| `datadog_metric_tag_configuration` | 1 | a configuração de tags de `http.server.request.duration` | `metrics.tf` |
| `datadog_dashboard` | 10 | 1 por serviço (4) + Visão Geral, Ordens de Serviço, Kubernetes, Sagas, Pagamentos e Mensageria | `dashboard_*.tf` |
| `datadog_monitor` | 30 | 5 por serviço (20) + 1 por Lambda (2) + 8 únicos | `monitors_*.tf` |
| `datadog_synthetics_test` | 4 | 1 por serviço | `synthetics.tf` |

Os cinco monitores por serviço são erros 5xx, latência p95, memória do pod, reinícios de contêiner e health
check degradado; os oito únicos são falhas no fluxo de ordens de serviço, falha de envio de e-mail, mensagem na
DLQ, mensagem inválida na DLQ, relay do outbox parado, webhook com assinatura inválida, compensações da aprovação de orçamento e falha na
limpeza do cache. Cada um está descrito em [Monitores](monitors.md).

Cada teste sintético cria implicitamente o seu próprio monitor no destino, exposto em `monitor_id`. É por isso
que a conta mostra 34 monitores para 30 recursos `datadog_monitor`.

A árvore de arquivos e a convenção de nomes estão em [Convenções](conventions.md).

---

## Os mapas de serviços e de Lambdas

Dois mapas em `locals.tf` são a fonte única do que é monitorado. Tudo que se repete por serviço ou por Lambda
é um bloco com `for_each` sobre um deles, e não uma cópia:

```hcl
services = {
  "work-order" = { service = "oficina-mecanica-work-order-service", kube_deployment = "work-order-service" }
  identity     = { service = "oficina-mecanica-identity-service", kube_deployment = "identity-service" }
  billing      = { service = "oficina-mecanica-billing-service", kube_deployment = "billing-service" }
  inventory    = { service = "oficina-mecanica-inventory-service", kube_deployment = "inventory-service" }
}

lambdas = {
  "customer-auth" = { function_name = "lbd-oficina-mecanica-customer-auth", service = "oficina-mecanica-lambda-customer-auth" }
  notification    = { function_name = "lbd-oficina-mecanica-notification", service = "oficina-mecanica-lambda-notification" }
}
```

**A chave de `services` é o contexto, e ele é também o namespace do Kubernetes e o segmento da rota pública de
saúde** (`/health/<contexto>` no gateway). `service` é o nome com que o serviço se identifica na telemetria e
`kube_deployment`, o nome do Deployment dele no cluster. Em `lambdas`, a chave é o nome curto da função,
`function_name` é o nome da função na AWS e `service`, o nome dela na telemetria.

**Os mapas são `locals` e não variáveis** porque o conjunto é pequeno, não muda por ambiente e só muda por Pull
Request revisado. Como variável, o mesmo valor ficaria repetido na declaração, no `terraform.tfvars` e no
`terraform.tfvars.example`. O motivo completo, com as alternativas, está na
[ADR 0006](adr/0006-monitoramento-por-servico.md).

Dos mapas saem, por chave, os escopos (`service_scope`, `service_log_scope`, `service_k8s_scope`,
`lambda_scope`), as tags (`service_tags`, `lambda_tags`), os endereços dos dashboards de serviço e os links de
log das mensagens de alerta. Saem também o escopo dos quatro serviços juntos (`services_scope`) e a lista de
namespaces do dashboard de Kubernetes (`kube_namespaces`: as chaves de `services` mais `platform`).

### Serviço novo é uma chave no mapa

Para monitorar um quinto serviço, acrescente uma chave a `local.services`. O serviço precisa antes seguir o
padrão dos atuais: emitir telemetria com `service` = `oficina-mecanica-<contexto>-service`, rodar no
Deployment `<contexto>-service` do namespace `<contexto>` e ter a rota `/health/<contexto>` publicada no
gateway.

O `terraform plan` dessa mudança mostra:

| O que muda | Quantidade |
| --- | --- |
| Criados: o dashboard `Serviço <contexto>`, o teste sintético da rota de saúde e os cinco monitores por serviço (erros 5xx, latência p95, memória do pod, reinícios de contêiner, health check degradado) | 7 recursos |
| Alterados no lugar: a Visão Geral (uma linha nova), o dashboard de Kubernetes (o namespace no filtro e um indicador de pods), o dashboard de Mensageria e os monitores de mensagem na DLQ, de relay do outbox parado e de falha na limpeza do cache (o serviço entra em `services_scope`) | 6 recursos |

Uma Lambda nova é uma chave em `local.lambdas`: o `plan` cria o monitor de erros de execução dela e acrescenta
um grupo à Visão Geral.

---

## Providers

```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    datadog = { source = "DataDog/datadog", version = ">= 4.20.0, < 5.0.0" }
    aws     = { source = "hashicorp/aws",   version = ">= 6.46.0, < 7.0.0" }
  }
}
```

**`>= 1.11.0`** é o piso de versão do Terraform em toda a solução. A configuração usa `templatestring`
(disponível desde 1.9) para renderizar a mensagem única dos monitores.

**O provider AWS não cria nada.** Ele existe para duas coisas: o backend S3 e a leitura do state do gateway.

**A faixa do provider Datadog é maior-ou-igual com teto de maior**, e `.terraform.lock.hcl` é versionado: a
faixa permite correção de defeito sem editar código, e o arquivo de trava garante que toda execução — sua e a
da esteira — use exatamente a mesma versão até que alguém rode `terraform init -upgrade` num Pull Request.

Por que HCL tipado e não JSON bruto: [ADR 0001](adr/0001-terraform-com-provider-datadog.md).

---

## Autenticação

```hcl
provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}
```

As duas chaves são `sensitive`, **sem valor padrão**, e chegam por `TF_VAR_`. Elas são usadas apenas no bloco
`provider`, que não é persistido: **nenhum segredo entra no state**.

`api_url` tem **valor padrão versionado** (`https://api.us5.datadoghq.com/`). Não é sigiloso, e versionar
torna a troca de site uma linha revisável em Pull Request — mesmo critério do `telemetry_site` no repositório
da Lambda. É por isso que não existe um segredo `DD_SITE`.

A chave de aplicação pertence a uma **service account** dedicada, com escopos mínimos. A lista completa e o
motivo de cada escopo estão em [CI/CD](ci-cd.md#inventário-de-configuração-externa).

---

## Estado

```hcl
backend "s3" {
  key          = "infra/prod-simulated/custom-monitoring/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

O bucket não é declarado no arquivo: ele vem da variável de Actions da organização `TF_STATE_BUCKET`, passada
no `terraform init` por `-backend-config="bucket=$TF_STATE_BUCKET"`, para que o nome possa ser trocado sem editar
arquivo versionado ([ADR 0004](adr/0004-state-no-s3-compartilhado.md)). O mesmo bucket dos demais repositórios da solução, sob chave própria. `encrypt` para criptografia em repouso;
`use_lockfile` para a trava nativa por arquivo de lock, que faz a segunda execução simultânea **falhar** em vez
de corromper o state.

**O acoplamento é deliberado e está declarado**: sem credenciais AWS válidas, nem o `plan` local
nem a entrega funcionam — mesmo que a mudança seja só de dashboard, que é um recurso puramente Datadog. O
raciocínio e a alternativa recusada estão em [ADR 0004](adr/0004-state-no-s3-compartilhado.md).

---

## State remoto consumido

Declarado em `data.tf`, separado de `providers.tf`:

```hcl
data "terraform_remote_state" "gateway" {
  backend = "s3"
  config  = { bucket = …, key = "infra/prod-simulated/api-gateway/terraform.tfstate", region = … }
}
```

Fornece um único valor: **`api_endpoint`**, o endereço público do gateway, ao qual cada teste sintético acrescenta `/health/<contexto>`.

O endereço é regenerado a cada reprovisionamento do laboratório. Uma variável com a URL exigiria edição manual
a cada subida e divergiria em silêncio no dia em que alguém esquecesse. Ler do state é o padrão com que os
repositórios da solução já se consomem.

**Consequência operacional, e ela importa**: com o gateway destruído, o state existe mas fica **sem outputs**, e
o `plan` falha com `This object does not have an attribute named "api_endpoint"`. Isso é correto — significa
que a entrega deste repositório faz parte do ritual de subida, **depois** da entrega do gateway. Ver o
[Runbook](runbook.md).

---

## Variáveis

Sete grupos, todos em `variables.tf`:

| Grupo | Variáveis | Onde o valor vive |
| --- | --- | --- |
| Identidade | `project_name`, `env`, `kube_cluster_name` | `terraform.tfvars`, versionado; serviços e Lambdas ficam nos mapas de `locals.tf` |
| Credenciais e destino | `datadog_api_key`, `datadog_app_key` (sensíveis, sem padrão), `datadog_api_url`, `datadog_app_url` | as duas primeiras por `TF_VAR_`; as outras, padrão versionado |
| Alerta e estado | `alert_emails`, `environment_online` | `TF_VAR_`, das variables do repositório |
| State remoto | `gateway_state_key`, `gateway_state_region`, `aws_region` | `terraform.tfvars` |
| Bucket do state do gateway | `gateway_state_bucket` | `TF_VAR_gateway_state_bucket`, preenchida pelos workflows com `TF_STATE_BUCKET` |
| Limiares | dezoito variáveis, uma por limiar de monitor (lista abaixo) | `terraform.tfvars`, versionado |
| Verificação externa | `synthetic_locations`, `synthetic_tick_every_seconds`, `synthetic_min_location_failed`, `synthetic_min_failure_duration_seconds`, `synthetic_response_time_ms` | `terraform.tfvars`, versionado |

Os dezoito limiares, com o valor de `terraform.tfvars`:

| Monitor | Variáveis | Valor |
| --- | --- | --- |
| Erros 5xx de cada serviço | `api_5xx_warning_count`, `api_5xx_critical_count` | 5 e 20 respostas em 10 min |
| Latência p95 de cada serviço | `api_latency_p95_warning_seconds`, `api_latency_p95_critical_seconds` | 1 s e 2 s |
| Falhas no fluxo de ordens de serviço | `work_order_5xx_warning_count`, `work_order_5xx_critical_count` | 2 e 5 respostas em 10 min |
| Memória do pod | `pod_memory_warning_percent`, `pod_memory_critical_percent` | 80 % e 90 % do limite |
| Reinícios de contêiner | `pod_restart_critical_count` | 0 |
| Erros de execução das Lambdas | `lambda_error_critical_count` | 0 |
| Falha de envio de e-mail | `notification_failure_warning_count`, `notification_failure_critical_count` | 2 e 5 eventos `notification.failed` em 15 min |
| Health check degradado | `health_degraded_critical_count` | 0 |
| Mensagem na DLQ e mensagem inválida na DLQ | `dead_letter_critical_count` | 0 |
| Relay do outbox parado | `outbox_publish_failure_critical_count` | 10 falhas em 5 min |
| Webhook com assinatura inválida | `webhook_invalid_signature_critical_count` | 3 recusas em 15 min |
| Compensações da aprovação de orçamento | `saga_compensation_critical_count` | 1 em 1 h |
| Falha na limpeza do cache | `cache_invalidation_critical_count` | 0 |

Os cinco limiares zerados — reinício de contêiner, erro de execução da Lambda, health check degradado,
mensagem na DLQ e falha na limpeza do cache — **não** são monitores desligados: o operador é `>`, então zero
significa "qualquer ocorrência é incidente". Continuam variáveis por uniformidade, e porque elevar um deles é
como um sinal comprovadamente ruidoso passa a ser tolerado. A origem de cada valor está na descrição da
variável e em [Monitores](monitors.md).

**Os limiares são variáveis, e não números no meio da consulta**, para que a calibração seja uma linha de
`.tfvars` num Pull Request cuja descrição cite os valores observados — e não uma edição de consulta que ninguém
consegue revisar. Ver [Monitores](monitors.md#calibração-de-limiar).

`alert_emails` é **string separada por vírgula**, não lista. `TF_VAR_` de tipo complexo exige sintaxe HCL dentro
de uma variável do provedor de código, que é frágil de editar; e-mails não contêm vírgula, então a separação é
inequívoca. **O valor não é versionado**: este repositório é público e endereço é dado pessoal.

---

## Locals

`locals.tf` cobre o reuso real, que é de cinco tipos:

| Local | Para quê |
| --- | --- |
| `services`, `lambdas`, `kube_namespaces` | os mapas descritos acima e a lista de namespaces derivada deles |
| `service_scope`, `service_log_scope`, `service_k8s_scope`, `lambda_scope` (mapas por chave) e `services_scope` | escopo de consulta compartilhado pelos dashboards e monitores |
| `common_tags`, `service_tags`, `lambda_tags`, `dashboard_tags` | tagging uniforme |
| `datadog_app_base`, `dashboard_url_*`, `logs_url_*`, `runbook_url` | links contextuais nas mensagens de alerta e no resumo da entrega |
| `alert_footer`, `monitor_message`, `synthetic_message` | as mensagens dos monitores e dos testes sintéticos, por estado |

**`datadog_dashboard.url` devolve caminho, não endereço absoluto** (`/dashboard/<id>/<slug>`). Concatenado com
`local.datadog_app_base`, vira link que funciona fora do Datadog — no resumo da execução do CD e no corpo do
e-mail de alerta. Sem isso, o caminho resolve contra o domínio de quem renderiza o markdown.

`monitor_message` e `synthetic_message` são templates renderizados por `templatestring` em cada monitor e em
cada teste sintético. Os `$${…}` no heredoc são escapados para chegarem **literais** ao template e só então
serem substituídos pelos valores do serviço — as chaves duplas `{{…}}` são do destino e passam intactas.

---

## Sem módulos

Um ambiente e um consumidor de cada definição. O que se repete por serviço ou por Lambda é um `for_each` sobre
o mapa, no próprio recurso. Um módulo aqui só acrescentaria indireção: quando um Pull Request altera a
consulta de um widget, o diff precisa exibir **a consulta alterada**, não uma chamada de módulo com um
parâmetro diferente.

Sem workspaces e sem diretório por ambiente, pela mesma razão: há um ambiente.

---

## Prevenção de desvio

O `terraform plan` **é** a detecção de desvio. Se alguém editar um dashboard ou um monitor pela interface do
Datadog, o próximo `plan` exibe a diferença e o próximo `apply` restaura a definição versionada.

Não há `lifecycle { ignore_changes }` em recurso algum, deliberadamente: ignorar mudança é abrir uma porta
para configuração que existe só na interface, que é exatamente o que este repositório foi criado para fechar.

**O `plan` também é a validação específica de Datadog.** Ele roda contra a API do destino e rejeita consulta
malformada, tag inexistente e widget inválido. Nenhum linter de terceiro acrescentaria isso, e é por isso que
o repositório não usa `tflint`, `checkov` nem `trivy config` — ver [CI/CD](ci-cd.md).

---

## Importação

Recursos da solução devem permanecer sob ownership exclusivo do Terraform. Se um recurso correspondente já
existir na conta fora do state, o caminho é um dos dois, nunca a convivência:

```bash
# importar para o state
terraform import datadog_dashboard.<nome> <id do dashboard>
terraform import datadog_monitor.<nome> <id do monitor>

# ou apagar da conta antes do próximo apply
```

Um recurso da solução que exista na conta e não no state é um recurso órfão, e ele não sobrevive à revisão.

---

## Reversão

Não há mecanismo próprio de reversão: o Terraform reconcilia declarativamente. Reverter uma entrega é
`git revert` do commit correspondente seguido de nova execução do CD.

Destruir tudo é possível (`terraform destroy`) mas raramente é o que se quer: dashboards e monitores **não
consomem recursos do laboratório** e sobrevivem à destruição do ambiente sem custo. O que precisa ser
alternado ao derrubar o ambiente são os testes sintéticos, pela variable `ENVIRONMENT_ONLINE` — ver o
[Runbook](runbook.md).
