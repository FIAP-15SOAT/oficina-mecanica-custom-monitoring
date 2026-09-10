# ADR 0001: Terraform com o provider Datadog, em HCL tipado

## Status

Aceito — 2026-09-09

## Contexto

A conta Datadog da solução recebe métricas, traces e logs da API, da Lambda e do cluster desde que a coleta foi
ligada, e **não tinha um único dashboard, monitor, objetivo de nível de serviço ou teste sintético**. O sinal
chegava e ninguém o lia.

Fechar essa lacuna significa criar dezesseis recursos na conta: quatro dashboards, nove monitores, um teste
sintético e quatro configurações de tag de métrica. A pergunta deste ADR é **como** eles passam a existir.

Duas restrições moldam a resposta:

1. **Este repositório existe para ser revisado em Pull Request.** É a razão de ele ser um repositório e não
   uma tarde de trabalho na interface. Uma consulta de alerta errada é indistinguível de uma certa até
   disparar — ou até deixar de disparar.
2. **Cerca de sessenta consultas compartilham o mesmo escopo** (`env`, `service`), as mensagens de monitor
   linkam dashboards cujos endereços só existem depois da criação, e os limiares aparecem tanto nos monitores
   quanto nos marcadores dos gráficos. Interpolação aqui é requisito, não conveniência.

## Decisão

Declarar tudo em **HCL tipado**, com os recursos `datadog_dashboard`, `datadog_monitor`,
`datadog_synthetics_test` e `datadog_metric_tag_configuration`, usando o provider `DataDog/datadog` na faixa
`>= 4.20.0, < 5.0.0`, com `.terraform.lock.hcl` versionado.

Sem módulos e sem workspaces: um ambiente e um consumidor de cada definição. O reuso real — escopo, tags,
links, mensagem — cabe em `locals`.

## Alternativas consideradas

| Alternativa | Por que não |
| --- | --- |
| **`datadog_dashboard_json`** (JSON bruto colado da interface) | Nenhuma validação de esquema até o `apply`: um widget malformado só falha na `main`, depois do merge. O diff de JSON aninhado é ruidoso a ponto de a revisão virar teatro. E a interpolação, que aqui é requisito, exigiria `templatefile()` — destruindo justamente o benefício de colar da interface |
| **`datadog_dashboard_v2`** | Declarado **beta/experimental** na documentação do provider. Um repositório que existe para ser a fonte de verdade não se apoia em recurso experimental |
| **JSON enviado por script ou `datadog-ci`** | Sem state, sem `plan`, sem detecção de desvio. Elimina a razão de ser do repositório: se alguém editar na interface, ninguém fica sabendo |
| **Criar na interface e não versionar** | Não é infraestrutura como código. É o estado atual, que este repositório existe para corrigir |

## Consequências

**Positivas**

- O `plan` do CI valida contra a API do destino e **rejeita consulta malformada, tag inexistente e widget
  inválido** antes do merge. É a validação específica de Datadog deste repositório, e é por isso que ele não
  usa `tflint`, `checkov` nem `trivy config`.
- O `plan` é também a detecção de desvio: edição pela interface aparece como diferença, e o `apply` seguinte
  restaura a definição versionada.
- O diff de um Pull Request exibe **a consulta alterada**, em uma linha legível.

**Negativas, e aceitas**

- Colar da interface deixa de funcionar: um widget desenhado na tela precisa ser traduzido para HCL à mão.
- O esquema do provider é um teto. Se um widget existir na interface e não no provider, ele não pode ser
  declarado.
- Há verbosidade: um widget de duas séries com apelido ocupa trinta linhas de HCL onde ocuparia dez de JSON.

## Escape hatch

Se algum widget futuro não existir no esquema do provider, **aquele dashboard** — e só ele — migra
isoladamente para `datadog_dashboard_json`, sem tocar em nada mais. A decisão não é um voto de fé no provider;
é a escolha do padrão, com a saída de emergência declarada.

## Gatilho de reavaliação

`datadog_dashboard_v2` sair de beta e cobrir os widgets em uso. A migração se justificaria só se ela trouxesse
validação melhor, não por ser mais nova.
