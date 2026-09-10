# ADR 0004: State no S3 compartilhado, com o acoplamento declarado

## Status

Aceito — 2026-09-09

## Contexto

Esta stack provisiona **apenas recursos Datadog**: dashboards, monitores, um teste sintético e configurações de
tag de métrica. Nenhum recurso AWS é criado aqui.

Mesmo assim ela precisa de um lugar para o state, e precisa de trava — o CD pode ser acionado manualmente
enquanto alguém roda `plan` no próprio computador, e duas execuções simultâneas sobre o mesmo state o
corrompem.

Há um segundo motivo, independente do primeiro, para a AWS entrar na equação: o teste sintético verifica o
endereço público do gateway, que é regenerado a cada reprovisionamento do laboratório. Ler esse endereço do
state do gateway exige credenciais AWS de qualquer forma — ver [ADR 0003](0003-uptime-por-verificacao-externa.md).

## Decisão

```hcl
backend "s3" {
  bucket       = "bkt-oficina-mecanica"
  key          = "infra/prod-simulated/custom-monitoring/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

O mesmo bucket dos outros cinco repositórios da solução, sob chave própria, seguindo a convenção de caminho já
estabelecida. `encrypt` para criptografia em repouso; `use_lockfile` para a trava nativa por arquivo de lock,
que dispensa a tabela DynamoDB do padrão antigo.

## O acoplamento, declarado

**Sem credenciais AWS válidas, nem o `plan` local nem a entrega funcionam** — mesmo que a mudança seja a
correção de um título de widget, que é um recurso puramente Datadog.

Isso está sendo aceito conscientemente, com esta justificativa: **se o laboratório está fora, a solução está
fora, e uma mudança de dashboard não é urgente.** O custo prático do acoplamento é próximo de zero, porque não
existe cenário realista em que se precise entregar uma mudança de monitoramento com o ambiente observado
destruído.

O CI trata as duas credenciais de forma diferente, e essa diferença é a mitigação: a da AWS recebe
`continue-on-error` e a sua falha **não reprova** — `fmt` e `validate` continuam sendo executados e são a
garantia estrutural. Só a prévia é pulada, com nota no resumo da execução.

## Alternativas consideradas

| Alternativa | Por que não |
| --- | --- |
| **HCP Terraform** (state gerenciado) | Elimina a dependência da AWS para o state — e introduz uma **sexta conta e ferramenta** na solução, com o seu próprio ciclo de credenciais, para resolver um acoplamento cujo custo prático é baixo. Também não elimina a dependência de verdade: o `api_endpoint` continuaria vindo do state do gateway, no S3 |
| **State local versionado** | Sem trava, com risco real de conflito entre a esteira e o computador de alguém, e com o histórico de recursos num repositório **público** |
| **Bucket próprio deste repositório** | Mais um bucket para criar e destruir a cada sessão do laboratório, sem ganho de isolamento — as mesmas credenciais de organização acessam os dois |
| **Sem state** (scripts idempotentes contra a API) | Elimina a razão de ser do repositório — ver [ADR 0001](0001-terraform-com-provider-datadog.md) |

## Consequências

- **Nenhum segredo entra no state.** As chaves do Datadog são usadas apenas no bloco `provider`, que não é
  persistido. O state contém definições de dashboard e de monitor, que não são sigilosas.
- A trava faz a segunda execução simultânea **falhar**, em vez de corromper. `cancel-in-progress: false` no CD
  existe pela mesma razão.
- O bucket é destruído junto com o laboratório? **Não** — ele é criado pelo `infra-base` e sobrevive à
  destruição das stacks, porque o state de todas elas mora nele. Mas se o bucket for perdido, o state deste
  repositório se perde junto, e os recursos Datadog viram órfãos: existem na conta e não no state.
- **Recuperação de state perdido**: importar os dezesseis recursos com `terraform import`, ou apagá-los da
  conta e reaplicar. O procedimento está em [Infraestrutura](../terraform.md#importação).

## Gatilho de reavaliação

O laboratório AWS Academy sair de cena — conta AWS permanente, ou a solução deixar de depender de infraestrutura
efêmera. Nesse caso o acoplamento deixa de ser um incômodo periódico e a decisão não precisa mudar; ela
simplesmente para de custar.
