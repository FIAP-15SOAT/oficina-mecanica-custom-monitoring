# Convenções

Nomenclatura e tagging deste repositório. Curto de propósito: uma convenção que ninguém lembra não é seguida.

---

## Nomes exibidos no Datadog

| Tipo | Padrão | Exemplos |
| --- | --- | --- |
| Dashboard | `Oficina Mecânica · <Área>` | `Oficina Mecânica · Visão Geral`, `Oficina Mecânica · API`, `Oficina Mecânica · Ordens de Serviço`, `Oficina Mecânica · Kubernetes` |
| Monitor | `[Oficina Mecânica] <Componente> · <Sintoma>` | `[Oficina Mecânica] API · Erros 5xx acima do limite`, `[Oficina Mecânica] Pod · Memória próxima do limite` |
| Teste sintético | mesmo padrão de monitor | `[Oficina Mecânica] Disponibilidade externa · rota pública indisponível` |

O separador é o **ponto médio** `·` (U+00B7), não hífen. Os colchetes existem só nos monitores, porque o
assunto do e-mail começa pelo nome do monitor e o prefixo entre colchetes é o que separa esta solução de
qualquer outra na caixa de entrada.

**O sintoma nomeia o que está errado, não a métrica.** `Memória próxima do limite`, não
`kubernetes.memory.working_set alto`. Quem recebe o alerta precisa saber o que está acontecendo antes de saber
de onde veio o número.

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
| Dashboards, teste sintético, M1 a M6, M8, M9 | `service:oficina-mecanica-api` |
| M7 | `service:oficina-mecanica-lambda-customer-auth` |

Em `terraform/locals.tf`: `local.common_tags`, `local.api_tags`, `local.lambda_tags`. Nenhum recurso declara
tags à mão.

**`env:production` na tag do recurso é o ambiente da solução**, e não necessariamente o valor que o componente
emite: M7 carrega `env:production` como recurso, mas **consulta** `functionname` e nunca `env`, porque a
Lambda emite `env:prod-simulated` (L8).

Filtrar a conta por `project:oficina-mecanica` lista todos os dashboards, monitores e testes sintéticos da
solução. É o que o widget `manage_status` da Visão Geral usa.

---

## Dimensões de consulta

**Reutilize as dimensões que a instrumentação já produz. Não crie taxonomia paralela.**

| Dimensão | Onde vale |
| --- | --- |
| `env`, `service`, `version` | métricas da API |
| `http.route`, `http.response.status_code` | `http.server.request.duration`, depois da configuração de tags |
| `oficina.work_order.status` | métricas de negócio (valores em **minúsculas**) |
| `db.operation.name`, `db.client.connection.state` | métricas de banco |
| `kube_deployment`, `pod_name`, `kube_namespace`, `kube_cluster_name` | métricas de Kubernetes |
| `functionname`, `cold_start`, `region` | métricas da Lambda |
| `@oficina.event.name`, `@oficina.work_order.status.current`, `@http.route` | facetas de log (valores no **enum de domínio**, maiúsculo) |

Uma consulta escrita com uma dimensão que a instrumentação não produz **é rejeitada na revisão**, e a dimensão
correta é localizada na instrumentação antes do merge. O inventário completo, com valores observados, está em
[Observabilidade](observability.md).

---

## Escopo de consulta

- **Nunca curinga irrestrito.** Toda consulta de métrica escopa por `env` e `service`, ou pela dimensão
  equivalente do componente (`kube_deployment`, `functionname`, `kube_cluster_name`).
- **Toda consulta de log escopa por `service`, por inclusão.** Nunca por exclusão: o índice recebe o cluster
  inteiro e listar o que não se quer é uma lista que envelhece (L7, L11).
- **Vírgula é `AND`.** Onde a consulta precisar de `OR`, a expressão inteira troca vírgulas por `AND`
  explícito — o destino recusa a mistura.

---

## Arquivos e recursos Terraform

Um arquivo por família. Sem módulos: um ambiente e um consumidor de cada definição não os justificam, e o
reuso real cabe em `locals`.

```
terraform/
├── backend.tf                  estado remoto
├── providers.tf                providers
├── data.tf                     o state remoto do gateway
├── variables.tf                entradas, incluindo todos os limiares
├── locals.tf                   escopos, tags, links, rodapé e a mensagem
├── outputs.tf                  endereços dos dashboards e identificadores
├── metrics.tf                  datadog_metric_tag_configuration
├── synthetics.tf               M1
├── dashboard_overview.tf       ┐
├── dashboard_api.tf            │ um arquivo por dashboard
├── dashboard_work_orders.tf    │
├── dashboard_kubernetes.tf     ┘
├── monitors_api.tf             M2, M3
├── monitors_work_orders.tf     M4
├── monitors_kubernetes.tf      M5, M6
├── monitors_lambda.tf          M7
└── monitors_integrations.tf    M8, M9
```

| Elemento | Padrão | Exemplo |
| --- | --- | --- |
| Arquivo de dashboard | `dashboard_<área>.tf` | `dashboard_work_orders.tf` |
| Arquivo de monitores | `monitors_<família>.tf` | `monitors_integrations.tf` |
| Nome do recurso | `snake_case`, descrevendo o **sintoma** | `datadog_monitor.pod_memory`, `datadog_monitor.api_5xx` |
| Variável de limiar | `<componente>_<sinal>_<severidade>_<unidade>` | `api_latency_p95_warning_seconds`, `pod_memory_critical_percent` |
| Local de escopo | `<componente>_scope` | `local.api_scope`, `local.k8s_scope`, `local.lambda_scope` |
| Local de link de log | `logs_url_<assunto>` | `local.logs_url_mail` |

**Nomes de recurso não repetem o tipo.** `datadog_monitor.pod_memory`, não
`datadog_monitor.pod_memory_monitor`.

---

## Idioma

- **Comentários de código, descrições de variável e nomes de recurso**: as descrições de `variables.tf` seguem
  o inglês dos demais repositórios de infraestrutura da solução; os comentários explicativos são em português,
  como no repositório da Lambda.
- **Tudo que o Datadog exibe** — título de dashboard, nome de monitor, título de widget, nota, mensagem de
  alerta — **é em português**, porque o público é o time.
- **Documentação**: português.

---

## O que a revisão de um Pull Request exige

1. Todo nome de métrica, tag e faceta **confirmado por consulta que devolve dados** — não por leitura do
   código de origem.
2. Consulta de alerta validada em `POST /api/v1/monitor/validate` antes do HCL.
3. Nome e tags conforme este documento.
4. Widget com `live_span`, título com unidade e uma só dimensão de quebra.
5. Documentação atualizada no documento certo, **sem duplicar consulta** que já viva em outro.
6. `terraform fmt -check -recursive` e `terraform validate` passando — o CI reprova sem eles.
7. Para monitor novo: a resposta à pergunta "o que a pessoa faz ao receber este e-mail?" escrita em
   [Monitores](monitors.md).
