# ADR 0003: Uptime por verificação externa

## Status

Aceito — 2026-09-09

## Contexto

O ADR 0005 do repositório `oficina-mecanica-api` exclui as rotas de saúde da instrumentação de entrada por
`ignoreIncomingRequestHook`. Uma probe do Kubernetes a cada poucos segundos, multiplicada por réplicas,
dominaria o volume de traces e métricas sem representar tráfego de usuário. A disponibilidade pública é,
portanto, medida pelo teste sintético externo declarado neste repositório.

O estado dos sinais confirma que **não existe caminho interno** para essa resposta:

- **Sem métrica** de `/api/health/ready` — a rota é excluída na entrada.
- **Sem trace** dela, pela mesma exclusão.
- **Sem log de sucesso** dela.
- **Sem métricas de API Gateway**, porque a integração AWS do destino exige criar uma role IAM e o laboratório
  AWS Academy não permite. Não é opcional: é impossível nesta conta.
- **Sem `kubernetes_state.*`**, porque não há Cluster Agent — então nem "quantas réplicas estão prontas" é
  observável.

Um sinal indireto — "há requisições chegando, logo a API está de pé" — não responde à pergunta: ausência de
tráfego num ambiente de demonstração é o normal, não um sintoma.

## Decisão

**Um teste sintético `api`/`http`, declarado neste repositório, é a fonte de verdade de disponibilidade.**

```
GET {api_endpoint}/api/health/ready
  statusCode is 200
  responseTime lessThan 5000 ms
```

Três localidades (`aws:us-east-1`, `aws:sa-east-1`, `aws:eu-west-1`), execução a cada 5 minutos, confirmação
com `min_location_failed = 2` e `min_failure_duration = 120`.

A exclusão das probes da instrumentação e o teste sintético externo são complementares: uma reduz ruído e o
outro mede o caminho público completo.

O endereço vem de `data.terraform_remote_state.gateway.outputs.api_endpoint`, e não de uma variável editada à
mão — ver [ADR 0004](0004-state-no-s3-compartilhado.md).

## Alternativas consideradas

| Alternativa | Por que não |
| --- | --- |
| **Reverter a exclusão das probes na API** | Resolveria a observabilidade da rota ao custo de reintroduzir exatamente o ruído que o ADR 0005 eliminou — e ainda assim mediria a saúde **de dentro**, que não é a pergunta. Um pod saudável atrás de um gateway quebrado continua invisível |
| **Monitor sobre volume de requisições** ("zero requisições em N minutos") | Ausência de tráfego é o normal neste ambiente. Dispararia todo dia |
| **Objetivo de nível de serviço com janela de 30 dias** | Sobre um ambiente deliberadamente desligado na maior parte do tempo, produz um número sem significado. Recusado; o requisito de uptime é atendido pela taxa de sucesso do teste na janela do dashboard |
| **Verificação por `check_status` de um agente** | Mede de dentro do cluster, como a probe. Não atravessa o gateway |
| **Uma única localidade** | Uma falha de rede regional seria lida como queda da aplicação, e quatro pessoas receberiam um alerta falso |

## O ambiente efêmero, e a alternância

O laboratório é ligado sob demanda e destruído ao final de cada sessão. Um teste sintético apontado para um
endereço que deixou de existir dispararia ao fim de **toda** sessão — quatro e-mails para quatro pessoas,
alguns dias por semana. Isso não é monitoramento; é treinamento para ignorar alertas.

Por isso o teste alterna:

```hcl
status = var.environment_online ? "live" : "paused"
```

Suspenso, ele não executa, não consome cota e não notifica — **e a definição permanece versionada**.

| Alternativa de suspensão | Por que não |
| --- | --- |
| `datadog_downtime_schedule` sobre `project:oficina-mecanica` | Silencia a notificação, mas o teste **continua executando** e consumindo cota contra um endereço inexistente |
| `count = var.environment_online ? 1 : 0` | Destrói e recria o teste a cada sessão, perdendo histórico e identificador — e o identificador é referenciado pelo widget de histórico da Visão Geral |
| Aceitar os alertas de derrubada | Ver acima |
| Entrada de `workflow_dispatch` em vez de variable | Duas fontes de verdade para o mesmo estado |

## Consequências

- Uptime é observável **de fora**, atravessando gateway, VPC Link, NLB e pod — a mesma
  cadeia que o usuário atravessa.
- **Alternar `ENVIRONMENT_ONLINE` vira passo obrigatório** dos rituais de subida e de derrubada, e o esquecimento
  tem consequência barulhenta. O passo está no [Runbook](../runbook.md), ao lado da renovação das credenciais.
- O apply deste repositório depende do endpoint exportado pelo gateway.
- A página do próprio teste no destino entrega mais que qualquer dashboard que se fizesse sobre ele —
  histórico por localidade, tempos por fase da requisição, corpo da resposta. Por isso um dashboard dedicado de
  disponibilidade foi recusado.
