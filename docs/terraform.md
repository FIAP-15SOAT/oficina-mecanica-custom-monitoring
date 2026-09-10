# Infraestrutura como código

Como a configuração do Datadog é declarada, versionada e reconciliada. A execução no seu computador está em
[Como executar localmente](local-setup.md); a execução na esteira, em [CI/CD](ci-cd.md).

---

## O que a stack provisiona

Catorze recursos, todos na conta Datadog `us5`. **Nenhum recurso AWS é criado aqui.**

| Recurso | Quantidade | Arquivo |
| --- | ---: | --- |
| `datadog_metric_tag_configuration` | 1 | `metrics.tf` |
| `datadog_dashboard` | 4 | `dashboard_*.tf` |
| `datadog_monitor` | 8 | `monitors_*.tf` |
| `datadog_synthetics_test` | 1 | `synthetics.tf` |

O teste sintético cria implicitamente o seu próprio monitor no destino, exposto em `monitor_id` — é o M1.

A árvore de arquivos e a convenção de nomes estão em [Convenções](conventions.md).

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
  bucket       = "bkt-oficina-mecanica"
  key          = "infra/prod-simulated/custom-monitoring/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

O mesmo bucket dos demais repositórios da solução, sob chave própria. `encrypt` para criptografia em repouso;
`use_lockfile` para a trava nativa por arquivo de lock, que faz a segunda execução simultânea **falhar** em vez
de corromper o state.

**O acoplamento é deliberado e está declarado**: sem credenciais válidas do laboratório AWS, nem o `plan` local
nem a entrega funcionam — mesmo que a mudança seja só de dashboard, que é um recurso puramente Datadog. O
raciocínio e a alternativa recusada estão em [ADR 0004](adr/0004-state-no-s3-compartilhado.md).

---

## State remoto consumido

Declarado em `data.tf`, separado de `providers.tf`:

```hcl
data "terraform_remote_state" "gateway" {
  backend = "s3"
  config  = { bucket = …, key = "infra/prod-simulated/gateway/terraform.tfstate", region = … }
}
```

Fornece um único valor: **`api_endpoint`**, o endereço público que o teste sintético verifica.

O endereço é regenerado a cada reprovisionamento do laboratório. Uma variável com a URL exigiria edição manual
a cada subida e divergiria em silêncio no dia em que alguém esquecesse. Ler do state é o padrão com que os
repositórios da solução já se consomem.

**Consequência operacional, e ela importa**: com o gateway destruído, o state existe mas fica **sem outputs**, e
o `plan` falha com `This object does not have an attribute named "api_endpoint"`. Isso é correto — significa
que a entrega deste repositório faz parte do ritual de subida, **depois** da entrega do gateway. Ver o
[Runbook](runbook.md).

---

## Variáveis

Três grupos, todos em `variables.tf`:

| Grupo | Variáveis | Onde o valor vive |
| --- | --- | --- |
| Identidade | `project_name`, `env`, `api_service`, `api_kube_deployment`, `kube_cluster_name`, `lambda_function_name` | `terraform.tfvars`, versionado |
| Credenciais e destino | `datadog_api_key`, `datadog_app_key` (sensíveis, sem padrão), `datadog_api_url`, `datadog_app_url` | as duas primeiras por `TF_VAR_`; as outras, padrão versionado |
| Alerta e estado | `alert_emails`, `environment_online` | `TF_VAR_`, das variables do repositório |
| State remoto | `gateway_state_*`, `aws_region` | `terraform.tfvars` |
| Limiares | doze variáveis, uma por limiar de monitor | `terraform.tfvars`, versionado |
| Verificação externa | `synthetic_locations`, `synthetic_tick_every_seconds`, `synthetic_min_location_failed`, `synthetic_min_failure_duration_seconds`, `synthetic_response_time_ms` | `terraform.tfvars`, versionado |

Os três limiares zerados — reinício de contêiner, erro de plataforma da Lambda, dependência degradada — **não** são monitores desligados: o operador é `>`, então zero significa "qualquer ocorrência é incidente". Continuam variáveis por uniformidade, e porque elevar um deles é como um sinal comprovadamente ruidoso passa a ser tolerado.

**Os limiares são variáveis, e não números no meio da consulta**, para que a calibração seja uma linha de
`.tfvars` num Pull Request cuja descrição cite os valores observados — e não uma edição de consulta que ninguém
consegue revisar. Ver [Monitores](monitors.md#calibração-de-limiar).

`alert_emails` é **string separada por vírgula**, não lista. `TF_VAR_` de tipo complexo exige sintaxe HCL dentro
de uma variável do provedor de código, que é frágil de editar; e-mails não contêm vírgula, então a separação é
inequívoca. **O valor não é versionado**: este repositório é público e endereço é dado pessoal.

---

## Locals

`locals.tf` cobre o reuso real, que é de quatro tipos:

| Local | Para quê |
| --- | --- |
| `api_scope`, `api_scope_and`, `k8s_scope`, `lambda_scope`, `log_scope`, `work_order_routes` | escopo de consulta compartilhado por ~60 consultas |
| `common_tags`, `api_tags`, `lambda_tags` | tagging uniforme |
| `logs_url_*` | links contextuais nas mensagens de alerta |
| `alert_footer`, `monitor_message`, `synthetic_message` | a mensagem única, por estado |

`monitor_message` é um template renderizado por `templatestring` em cada monitor. Os `$${…}` no heredoc são
escapados para chegarem **literais** ao template e só então serem substituídos — as chaves duplas `{{…}}` são
do destino e passam intactas.

---

## Sem módulos

Um ambiente, quatro dashboards, nove monitores, um consumidor de cada definição. Um módulo aqui só
acrescentaria indireção: quando um Pull Request altera a consulta de um widget, o diff precisa exibir **a
consulta alterada**, não uma chamada de módulo com um parâmetro diferente.

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

A conta não tinha dashboards, monitores nem testes sintéticos antes da primeira entrega: **não houve nada a
importar**. Se algum dia um recurso da solução for criado à mão na interface, o caminho é um dos dois, nunca a
convivência:

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
alternado ao derrubar o ambiente é o teste sintético, pela variable `ENVIRONMENT_ONLINE` — ver o
[Runbook](runbook.md).
