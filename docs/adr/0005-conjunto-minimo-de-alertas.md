# ADR 0005: Conjunto mínimo de alertas para um ambiente efêmero

## Status

Aceito — 2026-09-09

## Contexto

O plano exploratório deste repositório listava quinze candidatos a monitor. Nove sobreviveram. Este ADR
registra o critério e cada recusa, porque a pergunta "por que não temos um alerta para X?" vai voltar — e a
discussão precisa partir do motivo, não do zero.

Três fatos decidem quase tudo:

1. **O ambiente é efêmero.** O laboratório é ligado sob demanda e destruído ao final de cada sessão. Qualquer
   alerta que dependa de *presença* de dado dispara ao fim de toda sessão.
2. **O tráfego é esporádico.** Não há carga sustentada: há rajadas de demonstração separadas por horas de
   silêncio. Taxas calculadas sobre volume baixo são ruído.
3. **O time tem quatro pessoas, e não há plantão.** Todo alerta vai para os mesmos quatro endereços de e-mail.
   O orçamento de atenção é pequeno e não renovável: alertas que não exigem ação treinam o time a ignorar os
   que exigem.

O critério que sai daí é um só, e é aplicado a cada candidato:

> **O que a pessoa faz ao receber este e-mail?** Se a resposta for "olha e volta a dormir", é um widget de
> dashboard, não um monitor.

## Decisão

**Nove monitores**, listados e detalhados em [Monitores](../monitors.md):

| Monitor | Sintoma | Prioridade |
| --- | --- | --- |
| Disponibilidade externa | Rota pública indisponível (verificação externa) | P1 |
| API · Erros 5xx | Erros 5xx da API acima do limite, por rota | P2 |
| API · Latência p95 | Latência p95 acima do alvo | P3 |
| Ordens de Serviço | Falhas no fluxo de ordens de serviço | P2 |
| Pod · Memória | Memória do pod próxima do limite | P2 |
| Pod · Reinícios | Reinícios de contêiner | P3 |
| Lambda customer-auth | Erros de execução da Lambda | P2 |
| Integrações · E-mail | Falha de envio de e-mail | P4 |
| Dependência | Dependência degradada | P3 |

**Nenhum monitor tem `notify_no_data` ligado**, e é essa opção que torna seguro desligar o ambiente.

Uma janela vazia avalia como zero **apenas quando a série existe**. Quando ela nunca existiu — nenhum 5xx,
nenhum erro de plataforma na Lambda — o destino reporta `No Data`. Com a solução saudável, três dos nove
monitores ficam em `No Data`. Nenhum notifica, mas por causa de `notify_no_data = false`, não por aritmética
de contagem.

**Nenhum monitor tem `renotify_interval`.** Não há plantão para escalar, e repetir o alerta a cada N minutos
transforma a caixa de entrada em algo que se filtra.

### Contagem, não taxa, nos monitores de erro e de envio de e-mail

Com tráfego esporádico, uma taxa dispara com "1 erro em 3 requisições" — que é uma tarde normal de
demonstração. As taxas permanecem nos dashboards, onde informam sem acordar ninguém.

**Gatilho de migração para taxa**: volume sustentado acima de 10 req/min.

### A redundância entre os dois monitores de erro é assumida

Os monitores de erros 5xx e de ordens de serviço disparam juntos numa indisponibilidade total, e isso **não é um defeito a corrigir**. São leituras
distintas — *"a API está falhando"* e *"o fluxo de negócio está quebrado"* — para públicos distintos, e a
segunda nomeia o impacto que a primeira não nomeia.

| Alternativa avaliada | Por que não |
| --- | --- |
| **Monitor composto** (um `AND NOT` do outro) | Cerimônia desproporcional: acrescenta um recurso, uma indireção e uma classe nova de defeito para evitar um e-mail duplicado ocasional |
| **Um único monitor agrupado por rota** | Perderia a nomeação do impacto de negócio, que é o requisito do monitor de ordens de serviço |
| **Excluir as rotas de negócio do escopo do monitor de erros 5xx** | Uma falha geral deixaria de aparecer no alerta de API, que é justamente o alerta que se olha primeiro |

## Alertas recusados

| Recusado | Motivo | Gatilho para reabrir |
| --- | --- | --- |
| **Coleta interrompida** | Seu disparo seria **garantido** ao final de toda sessão do laboratório. É o exemplo mais claro do critério: o alerta seria disparado por um evento planejado | O ambiente passar a ser permanente |
| **CPU alta** | Com autoescalonamento mirando 70 % de CPU, "CPU alta" é o mecanismo **funcionando**. Alertar sobre isso é alertar sobre o sucesso | Estrangulamento sustentado correlacionado com a latência da API |
| **Estrangulamento de CPU** | É o sinal acionável que "CPU alta" não é — mas, sem evidência de que ele preceda degradação percebida nesta aplicação, seria um alerta em busca de um problema. Fica no dashboard de Kubernetes | A latência da API disparar com estrangulamento como causa recorrente |
| **Nenhuma OS criada em 24 h** | Dispararia todo dia. Num ambiente ligado algumas horas por semana, "nenhuma ordem criada" é o estado normal | Ambiente permanente com uso real |
| **Permanência média por status acima de X** | Não existe acordo de negócio que defina o X. Inventar um limiar produz um alerta permanentemente vermelho ou permanentemente verde, e os dois são inúteis | O negócio declarar um acordo de nível de serviço |
| **Latência de banco em monitor próprio** | Sem latência de API alta, latência de banco alta não é incidente. Com ela, o monitor de latência já disparou e o dashboard de API mostra a causa no grupo Banco | — |
| **Descarte de span pelo canal `diag` do OTel** | Descarte por fila cheia é comportamento **declarado como aceito** no ADR 0005 da API. Alertar contrariaria a decisão de origem — e o alerta certo, se um dia for necessário, pertence àquele repositório | A API reabrir aquela decisão |
| **Qualquer monitor sobre `kubernetes_state.*`** | Não existe: não há Cluster Agent na instalação (L1) | Instalar o Cluster Agent |
| **Timeouts e falta de memória da Lambda, em monitores próprios** | Ambos incrementam `aws.lambda.enhanced.errors`, que o monitor de erros de execução já observa. Seriam três e-mails para o mesmo evento | — |
| **Objetivo de nível de serviço** | Janela fixa de 30 dias sobre um ambiente desligado na maior parte do tempo produz um número sem significado | Ambiente permanente |

## Limiares: origem declarada

**Os limiares de latência são valores de percepção de usuário, não percentis observados**, e estão declarados como
tais. O único dado medido — p95 de 23,5 ms no compose local, ADR 0005 da API — não representa produção.

Isso é uma dívida conhecida, não um descuido. Ela é paga pelo procedimento de calibração do
[Runbook](../runbook.md): após uma semana com tráfego representativo, reler p95 e p99 reais e ajustar para 2×
e 4×, **em Pull Request cuja descrição cite os valores medidos**.

Todos os limiares são variáveis em `terraform/variables.tf`, com valores em `terraform/terraform.tfvars`,
justamente para que a calibração seja uma linha revisável e não uma edição de consulta.

## Consequências

- Quatro e-mails por evento, para quatro pessoas, e nada além disso. O orçamento de atenção é gasto só onde há
  ação.
- **Nove monitores não cobrem tudo**, e não deveriam. As lacunas conhecidas — estado do cluster, API Gateway,
  RDS, traces da Lambda — estão documentadas como limitações em
  [Observabilidade](../observability.md#3-limitações), com a causa de cada uma.
- **Os monitores de e-mail e de dependência degradada não podem ser verificados de ponta a ponta** sem provocar o evento na origem: `mail.send.failed` e
  `health.degraded` têm zero ocorrências no índice. Estão marcados assim na documentação, e não como
  "funcionando".
- **O monitor de erros da Lambda avalia em `No Data`, não em `OK`**, na operação normal, porque `aws.lambda.enhanced.errors` só passa a
  existir na primeira falha. Não notifica, e é o comportamento desejado.

## Gatilho de reavaliação

O ambiente passar a ser permanente reabre, de uma vez: coleta interrompida, objetivo de nível de serviço,
"nenhuma OS criada em 24 h" e a migração de contagem para taxa. Quatro decisões, um único fato.
