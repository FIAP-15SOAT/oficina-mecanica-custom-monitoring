# Runbook

O que fazer quando um alerta chega, e o ritual de subida e derrubada do ambiente.

---

## Antes de tudo: o ambiente é efêmero

O laboratório AWS Academy é ligado sob demanda e **destruído ao final de cada sessão**. Isso muda a leitura de
qualquer alerta:

- **Nenhum monitor notifica por ausência de dado.** Se você recebeu um e-mail, algo **aconteceu** — não é o
  ambiente estando fora.
- Dashboard vazio com o laboratório fora é o estado esperado, não incidente.
- O endereço público muda a cada reprovisionamento, e por isso a entrega deste repositório faz parte do ritual
  de subida.

---

## Ritual de subida do ambiente

1. **Iniciar o laboratório** no AWS Academy e copiar as credenciais da sessão.
2. **Renovar os três segredos AWS de organização** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
   `AWS_SESSION_TOKEN`. Sem isso, toda esteira da solução falha.
3. **Executar as entregas na ordem de dependência**, em camadas. O script `environment-up.sh` do
   repositório `oficina-mecanica-infra-base` executa essa ordem sozinho; o detalhe está no
   [runbook dele](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base/blob/main/docs/runbook.md):

   | Camada | Repositórios | Por que depende da anterior |
   | ---: | --- | --- |
   | 1 | `oficina-mecanica-infra-base` | VPC e subnets |
   | 2 | `oficina-mecanica-infra-k8s`, `oficina-mecanica-infra-messaging` (tópico SNS e filas SQS) e os quatro bancos: `oficina-mecanica-infra-database-work-order`, `-identity`, `-billing` e `-inventory` | precisam da rede; o k8s publica o listener do NLB, o balanceador de rede interno do cluster |
   | 3 | `oficina-mecanica-work-order-service`, `oficina-mecanica-identity-service`, `oficina-mecanica-billing-service` e `oficina-mecanica-inventory-service` | precisam do cluster, das filas e do banco de cada um |
   | 4 | `oficina-mecanica-api-gateway` | precisa do listener do NLB; **publica `api_endpoint`** e as rotas `/health/<contexto>` |
   | 5 | `oficina-mecanica-lambda-customer-auth` e `oficina-mecanica-lambda-notification` | precisam da rede, da fila `notification.fifo` e do identity |
   | 6 | **`oficina-mecanica-custom-monitoring`** | **precisa de `api_endpoint`** |

4. **Ajustar `ENVIRONMENT_ONLINE` para `true`** nas variables deste repositório.
5. **Executar o CD deste repositório** (`workflow_dispatch`). O resumo da execução publica os endereços dos dez
   dashboards e o estado dos quatro testes sintéticos — confirme que saíram `live`.
6. Conferir, na página de cada teste sintético, que ele voltou a executar e está verde.

**Se este repositório for entregue antes do gateway**, a entrega falha com
`This object does not have an attribute named "api_endpoint"`. É o comportamento correto: o repositório está
avisando que o alvo ainda não existe.

---

## Ritual de derrubada do ambiente

1. **Ajustar `ENVIRONMENT_ONLINE` para `false`.**
2. **Executar o CD deste repositório** e confirmar, no resumo, que os testes sintéticos saíram `paused`.
3. Confirmar na página dos testes que **não há novas execuções** depois da entrega.
4. Só então destruir o restante do ambiente, na **ordem inversa** da subida.
5. Encerrar o laboratório.

**Este é o passo esquecido.** Deixar `ENVIRONMENT_ONLINE` em `true` depois de destruir o ambiente reintroduz
exatamente o ruído que o desenho eliminou: os quatro testes continuam executando contra um endereço
inexistente, consumindo cota, e cada alerta de disponibilidade dispara um e-mail para cada pessoa do time ao fim
de toda sessão. Alguns dias disso e o
time aprende a ignorar todos os alertas — o oposto do objetivo deste repositório.

Dashboards, monitores e configurações de métrica **não** precisam ser destruídos: eles não consomem recurso do
laboratório e não têm custo enquanto não há dado fluindo.

---

## O que fazer quando cada monitor dispara

### Disponibilidade externa

**Prioridade:** P1

A rota pública de saúde de um serviço (`/health/<contexto>`, nomeada no alerta) falhou em ao menos duas das três
localidades por mais de dois minutos.

1. **O ambiente deveria estar no ar?** Se foi derrubado sem ajustar `ENVIRONMENT_ONLINE`, o alerta é falso —
   execute o ritual de derrubada e o incidente acaba aqui.
2. Abra a página do teste sintético: veja **qual** asserção falhou (`statusCode` ou `responseTime`) e em quais
   localidades. Uma só localidade falhando é rede, não aplicação — mas então o monitor não teria disparado.
3. Verifique o dashboard de Kubernetes, indicador **Pods emitindo métrica** do namespace do serviço: se zero, o
   problema é o cluster ou o Deployment, não a aplicação. Se os quatro testes falharam juntos, o problema é
   comum a todos: gateway, NLB ou cluster.
4. Verifique o gateway na AWS: o `api_endpoint` mudou? Se sim, o `apply` deste repositório não rodou depois da
   entrega do gateway.
5. Se os pods estão de pé e o endereço está certo, siga para o dashboard do serviço: latência e erros. O alerta
   de health check degradado do mesmo serviço, se disparou, diz qual dependência falhou.

### Erros 5xx acima do limite

**Prioridade:** P2

1. Abra o [dashboard do serviço](dashboards.md#oficina-mecânica--serviço-contexto) nomeado no alerta. A
   **tabela de rotas** diz se o problema é de uma rota ou geral.
2. Grupo **Erros**: o `log_stream` já está filtrado em `status:error`. Leia `@oficina.error.message` e
   `@error.type`.
3. Grupo **Banco**: `pending_requests` subindo indica saturação de pool, que se manifesta como 5xx por tempo
   esgotado.
4. Grupo **Chamadas de saída**: um 5xx que acompanha falhas ou lentidão de outro serviço (`server.address`)
   vem dele; siga para o dashboard do serviço chamado.
5. Grupo **Runtime**: `nodejs.eventloop.delay.p99` alto indica bloqueio de event loop.
6. Se o alerta de ordens de serviço disparou junto, o impacto atinge o fluxo de negócio — priorize.

### Latência p95 acima do alvo

**Prioridade:** P3

1. **Antes de tratar como incidente, verifique se o limiar é o problema.** Os valores são de percepção de
   usuário, não percentis observados — veja a calibração abaixo.
2. Dashboard do serviço, grupo **Latência**: o top 10 rotas por p95 diz onde.
3. Grupo **Banco**: a média de `db.client.operation.duration` subiu junto? A causa é o banco.
4. Grupo **Runtime**: event loop e heap.
5. Dashboard de Kubernetes: **estrangulamento de CPU** sustentado explica latência sem explicar erro.

### Falhas no processamento de ordens de serviço

**Prioridade:** P2

O mesmo procedimento do alerta de erros 5xx, restrito às rotas de ordem de serviço, no work-order, e de
orçamento, no billing; o alerta nomeia o serviço e a rota. A diferença é o público: aqui há impacto de negócio
nomeado, e a comunicação para fora do time é diferente.

Se os dois alertas de erro dispararam juntos, é a mesma falha vista de dois ângulos. **Isso é esperado e está documentado**
como redundância assumida.

### Memória do pod próxima do limite

**Prioridade:** P2

1. Dashboard de Kubernetes, grupo **Memória**: qual pod, e a curva é crescimento contínuo ou pico?
2. **Crescimento contínuo sem platô é vazamento.** Grupo **Runtime** do dashboard do serviço:
   `v8js.memory.heap.used` acompanha?
3. Em `critical` (90 %), o encerramento por falta de memória é iminente. Se o alerta de reinícios disparar em seguida, ele
   aconteceu.
4. Mitigação imediata: reiniciar o Deployment. Correção: investigar o vazamento ou subir o limite no
   repositório do serviço nomeado no alerta.

### Reinícios de contêiner

**Prioridade:** P3

1. Dashboard de Kubernetes, grupo **Ciclo de vida**: quantos pods e com que frequência.
2. **O alerta de memória disparou antes?** Então foi encerramento por falta de memória.
3. Reinício logo após uma entrega é provavelmente falha de inicialização — verifique os logs do pod.
4. Reinícios repetidos no mesmo pod indicam `CrashLoopBackOff`.
5. Um reinício isolado logo após provisionamento pode ser normal; `new_group_delay` de 600 s existe para
   filtrar a maior parte disso.

### Erros de execução da Lambda

**Prioridade:** P2

Vale para as duas funções Lambda da solução, nomeadas no alerta: a customer-auth (login do cliente) e a
notification (envio de e-mail).

1. **Qualquer erro aqui é defeito.** Erro de plataforma é a execução da função que falhou (exceção não tratada,
   prazo esgotado, falta de memória), não uma resposta de negócio: a customer-auth devolve 401 como resposta
   normal de credencial inválida, e a notification devolve à fila a mensagem que não conseguiu enviar e registra
   `notification.failed`, visto pelo alerta de falha de envio de e-mail.
2. Visão Geral, grupo **Lambda** da função: erros contra invocações, e a duração.
3. O link de logs da mensagem já está filtrado em `service:<serviço da função> status:error`.
4. Duração próxima do limite de execução ⇒ expiração de prazo. `max_memory_used` próximo de `memorysize` ⇒
   falta de memória. Ambos incrementam `errors`.
5. A customer-auth não emite traces: os logs são a única evidência dela. A notification registra um span por
   mensagem, dentro do trace de quem pediu o e-mail.

### Falha de envio de e-mail

**Prioridade:** P4

1. A mensagem nomeia o **motivo** e o **tipo de e-mail** (propósito) que falhou. O motivo decide a ação:
   `smtp_error` é o servidor de e-mail recusando ou fora do ar, `invalid_message` é uma mensagem da fila que a
   Lambda notification não consegue ler.
2. P4 significa que isto **não interrompe o fluxo principal**: a ordem de serviço avança, a notificação não sai.
3. O link de logs da mensagem já está filtrado no evento.

### Health check degradado

**Prioridade:** P3

1. A mensagem nomeia o **serviço**, a **dependência** verificada (hoje só o banco, `postgresql`) e a **categoria
   da falha**: `timeout` (prazo esgotado), `connection` (sem conexão), `pool` (pool de conexões saturado),
   `authentication` (credencial recusada), `query` (consulta falhou) ou `unknown`.
2. Com o banco degradado, os alertas de erro e de latência do mesmo serviço provavelmente dispararão em seguida —
   trate a causa aqui.
3. É o único sinal que nomeia a dependência: a rota de saúde não é observável por métrica nem trace (L3).

### Mensagem na DLQ

**Prioridade:** P2

Os serviços trocam comandos e eventos por filas SQS FIFO (filas que entregam na ordem de envio), uma por
consumidor: `work-order.fifo`, `billing.fifo` e `inventory.fifo`. Uma mensagem que falha 5 vezes seguidas vai
para a DLQ (dead-letter queue, a fila de mensagens desistidas) da fila, `<consumidor>-dlq.fifo`, e a ordem de
serviço a que ela pertence fica parada até a mensagem voltar. O alerta nomeia o **serviço** consumidor, a
**fila** e o **tipo** da mensagem (por exemplo, `inventory.stock.reserve`, o pedido de reserva de estoque).

1. Abra o link de logs da mensagem: ele mostra o evento `messaging.message.dead_lettered`, com o erro que fez o
   consumidor desistir e o id da ordem de serviço.
2. Siga o `trace_id` do evento até a falha original: banco fora do ar, defeito no código ou mensagem fora do
   formato esperado.
3. **Corrija a causa antes de devolver a mensagem.** Sem isso, ela volta a falhar 5 vezes e cai de novo na DLQ.
4. Devolva as mensagens à fila de origem com `aws sqs start-message-move-task`, que aceita fila FIFO quando o
   destino também é FIFO. O procedimento completo, com as esperas, está no
   [runbook do repositório de mensageria](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-messaging/blob/main/docs/runbook.md#redrive-de-uma-dlq):

   ```bash
   # ARN da DLQ do consumidor nomeado no alerta (troque inventory pelo consumidor)
   DLQ_URL=$(aws sqs get-queue-url --queue-name inventory-dlq.fifo --query QueueUrl --output text)
   DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)

   # Devolver as mensagens à fila de origem
   aws sqs start-message-move-task --source-arn "$DLQ_ARN"

   # Acompanhar até o status COMPLETED
   aws sqs list-message-move-tasks --source-arn "$DLQ_ARN"
   ```

5. **Verificação:** no dashboard de Mensageria, o consumo da fila volta a mostrar `success`, e no de Sagas a
   Saga da ordem de serviço termina. O monitor se recupera sozinho quando nenhuma mensagem nova vai para a DLQ
   na janela de 10 minutos.

A fila `notification.fifo`, da Lambda notification, não aparece aqui: quem a vigia é o alerta de falha de envio
de e-mail.

### Mensagem inválida na DLQ

**Prioridade:** P2

O consumidor desistiu de uma mensagem cujo corpo não é um envelope válido (JSON com `messageId`, `type`,
`occurredAt` e `payload`), por isso o alerta nomeia só o **serviço** e a **fila**, sem o tipo. Os serviços da
solução publicam sempre pelo outbox, com envelope válido: uma mensagem assim veio de fora do fluxo normal, por
exemplo de um envio manual à fila. **Não a devolva à fila de origem**: ela falharia de novo nas 5 tentativas.

1. Abra o link de logs: o evento `messaging.message.dead_lettered` traz o erro do consumidor (por exemplo,
   `Corpo da mensagem não é um JSON válido`) e o `messaging.message.id`, o id da mensagem no SQS.
2. Leia as mensagens da DLQ do consumidor nomeado no alerta, sem apagá-las:

   ```bash
   # URL da DLQ do consumidor nomeado no alerta (troque work-order pelo consumidor)
   DLQ_URL=$(aws sqs get-queue-url --queue-name work-order-dlq.fifo --query QueueUrl --output text)

   # Ler até 10 mensagens com id, recibo e corpo; elas voltam a ficar visíveis depois de 60 s
   aws sqs receive-message --queue-url "$DLQ_URL" --max-number-of-messages 10 --visibility-timeout 60      --query 'Messages[].[MessageId,ReceiptHandle,Body]'
   ```

3. Descubra quem enviou a mensagem (um envio manual, um teste, um produtor fora do outbox) e corrija a origem.
4. Apague da DLQ a mensagem com o `MessageId` do passo 1, usando o `ReceiptHandle` lido no passo 2 antes que os
   60 s acabem (se acabarem, leia de novo):

   ```bash
   # Apagar a mensagem inválida da DLQ
   aws sqs delete-message --queue-url "$DLQ_URL" --receipt-handle '<ReceiptHandle>'
   ```

5. **Verificação:** o monitor se recupera sozinho quando nenhuma mensagem inválida nova vai para a DLQ na janela
   de 10 minutos.

### Relay do outbox parado

**Prioridade:** P2

Cada serviço grava a mensagem que vai publicar numa tabela `outbox` do próprio banco, na mesma transação da
mudança de negócio, e um laço do serviço (o relay) a publica no tópico SNS `oficina-events.fifo` a cada meio
segundo. Para não furar a ordem, o relay para no primeiro erro do lote e tenta de novo no ciclo seguinte. Cada
tentativa que falha registra `messaging.outbox.publish_failed`; acima do limiar na janela de 5 minutos, a
falha é persistente e **todas** as mensagens daquele serviço estão presas.

1. Abra o link de logs da mensagem e leia o erro de `messaging.outbox.publish_failed` do serviço nomeado.
2. Erro de autorização (`AccessDenied`, `ExpiredToken`): a credencial que o nó do cluster usa para publicar
   expirou ou perdeu a permissão de `sns:Publish` no tópico.
3. Tópico não encontrado (`NotFound`): o tópico foi destruído ou o serviço aponta para outro ARN, configurado
   em `MESSAGING_TOPIC_ARN`.
4. Tempo esgotado ou erro de rede: o SNS está inacessível a partir do cluster.
5. **Verificação:** depois da correção, o relay publica as linhas pendentes sozinho, sem reiniciar o serviço.
   O monitor se recupera na janela seguinte, e o consumo das filas volta a subir no dashboard de Mensageria.

Uma falha isolada, publicada no ciclo seguinte, fica abaixo do limiar e aparece só no dashboard de Mensageria.

### Webhook com assinatura inválida

**Prioridade:** P2

O Mercado Pago, o provedor de pagamento, avisa o billing de cada mudança de cobrança por uma notificação HTTP
(webhook) assinada com uma chave secreta. O billing recusa a notificação cuja assinatura não confere e registra
`payment.webhook.invalid_signature`. Acima do limiar, ou a chave configurada no billing diverge da do painel do
Mercado Pago, e nenhuma cobrança é atualizada, ou alguém está tentando forjar notificações.

1. Abra o link de logs da mensagem: muitas recusas seguidas, depois de uma troca de chave ou de uma entrega do
   billing, apontam para chave divergente; recusas esparsas de origem desconhecida, para tentativa de forjar.
2. Confira no painel do Mercado Pago a URL do webhook e a chave secreta, pelo
   [runbook do billing](https://github.com/FIAP-15SOAT/oficina-mecanica-billing-service/blob/main/docs/runbook.md#url-do-webhook-no-painel).
3. Se a chave mudou, grave a nova no billing pela
   [troca da chave secreta do webhook](https://github.com/FIAP-15SOAT/oficina-mecanica-billing-service/blob/main/docs/runbook.md#troca-da-chave-secreta-do-webhook).
4. **Verificação:** use **Simular notificação** no painel do Mercado Pago e confira, no dashboard de
   Pagamentos, os webhooks voltando a sair como `valid`. Cobrança que continuar `PENDING` depois da correção
   segue a [cobrança presa](https://github.com/FIAP-15SOAT/oficina-mecanica-billing-service/blob/main/docs/runbook.md#cobrança-presa)
   do runbook do billing.

### Compensações de Saga

**Prioridade:** P3

A aprovação de um orçamento atravessa três serviços numa Saga (`QUOTE_APPROVAL`), uma transação distribuída
conduzida pelo work-order: o billing aprova, o inventory reserva as peças e o work-order muda a ordem de
serviço. Se um passo falha, a Saga é compensada: os passos já feitos são desfeitos e a aprovação é revertida.
Uma compensação isolada é desfecho de negócio; mais de uma na janela de 1 hora pede investigação. As Sagas de
pagamento (`PAYMENT`) não entram no alerta, porque cobrança recusada, expirada ou cancelada é desfecho normal.

1. Dashboard de Sagas, grupo **Compensações por motivo**: o motivo (`oficina.saga.failure_reason`) diz qual
   passo falhou.
2. `INSUFFICIENT_STOCK` (falta de estoque): confira o saldo das peças no inventory; a ação é de negócio
   (reposição), não técnica.
3. Outro motivo: siga o `trace_id` do evento `saga.compensated`, no link de logs da mensagem, até o serviço que
   recusou o passo.
4. **Verificação:** novas aprovações terminam `completed` no dashboard de Sagas. O limiar é provisório: calibre
   pela seção de contagem abaixo depois de uma semana de tráfego.

### Falha na limpeza do cache

**Prioridade:** P3

Cada serviço guarda no próprio cache (Valkey, compatível com Redis) as leituras por id, e apaga a chave
afetada depois de confirmar uma escrita. Quando a exclusão falha, o serviço registra `cache.invalidation_failed`
e a leitura seguinte devolve o valor antigo até a chave expirar, em até 12 horas.

1. Abra o link de logs da mensagem: o evento nomeia o serviço e traz o erro do cache. Siga o `trace_id` dele
   até a requisição ou mensagem que fez a escrita para saber qual registro mudou.
2. Se o cache já responde, apague a chave desse registro para não esperar a expiração, com
   `valkey-cli --tls -h "$CACHE_HOST" -p 6379 -a "$CACHE_TOKEN" --no-auth-warning DEL <chave>` num pod efêmero
   no namespace do serviço. O pod, o endereço e o token são os do teste de conexão a partir do cluster, no README do
   repositório de dados do serviço:

   | Serviço | Chaves | Repositório de dados |
   | --- | --- | --- |
   | work-order | `work-order:work-order:<id>` | [`oficina-mecanica-infra-database-work-order`](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-database-work-order/blob/main/README.md#teste-de-conexão-a-partir-do-cluster) |
   | identity | `identity:user:<id>` | [`oficina-mecanica-infra-database-identity`](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-database-identity/blob/main/README.md#teste-de-conexão-a-partir-do-cluster) |
   | billing | `billing:quote:<id>` e `billing:work-order-quotes:<workOrderId>` | [`oficina-mecanica-infra-database-billing`](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-database-billing/blob/main/README.md#teste-de-conexão-a-partir-do-cluster) |
   | inventory | `inventory:service:<id>` e `inventory:part-supply:<id>` | [`oficina-mecanica-infra-database-inventory`](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-database-inventory/blob/main/README.md#teste-de-conexão-a-partir-do-cluster) |

3. Se o cache continua inacessível, a chave expira sozinha em até 12 horas; o mesmo teste de conexão diz se o
   problema é rede, senha ou o próprio cache.
4. **Verificação:** a leitura por id devolve o valor novo, e o monitor se recupera na janela seguinte de 10
   minutos.

---

## Calibração de limiares

Fazer **depois de uma semana com tráfego representativo**, não antes.

### Latência

1. Dashboard de cada serviço, grupo **Latência**, janela de 7 dias. Leia o **p95** e o **p99** típicos,
   ignorando picos de provisionamento.
2. Os limiares valem para os quatro serviços. Use o **maior** p95 típico entre eles: novos limiares
   `warning = 2 × p95 observado`, `critical = 4 × p95 observado`. Se um serviço for muito mais lento que os
   outros por natureza, o Pull Request propõe limiares por serviço em vez de esconder a diferença.
3. Ajuste `api_latency_p95_warning_seconds` e `api_latency_p95_critical_seconds` em
   `terraform/terraform.tfvars`.
4. **Abra Pull Request citando os valores observados na descrição.** Um limiar sem justificativa registrada é
   um número inventado, e a próxima pessoa não saberá se pode mexer.

### Contagem — erros 5xx, ordens de serviço, envio de e-mail e limiares provisórios

1. Some os 5xx reais da semana no dashboard de cada serviço, por rota.
2. Para os limiares provisórios, compare com o volume da semana: falhas de publicação do outbox por serviço
   (dashboard de Mensageria), webhooks com assinatura inválida (Pagamentos) e compensações de
   `QUOTE_APPROVAL` por hora (Sagas).
3. Se algum monitor disparou por falso positivo, suba o limiar. Se um incidente real passou sem alerta,
   desça-o.
4. Mesmas variáveis, mesmo Pull Request com valores na descrição. A lista das variáveis está em
   [Infraestrutura](terraform.md#variáveis).

### Cota de custom metrics

1. `Organization Settings → Usage → Custom Metrics` na conta.
2. Compare com a estimativa de ~3.960 em [Observabilidade](observability.md#5-custo-de-custom-metrics) e
   **registre o consumo real lá**.
3. Se a cota apertar, acione a alavanca: remova `http.response.status_code` da lista de tags de
   `http.server.request.duration` em `terraform/metrics.tf`. Isso derruba a estimativa de ~3.960 para ~660, e
   move "erro por rota" para os logs.
4. **Consequência a considerar antes**: os monitores de erros 5xx e de ordens de serviço perdem a base de métrica e teriam de virar monitores de log.

---

## Quando um dashboard ou monitor foi alterado pela interface

O próximo `terraform plan` exibe a diferença e o próximo `apply` **restaura a definição versionada**. Se a
alteração era desejada, ela precisa virar Pull Request. Não há `ignore_changes` em recurso algum, e isso é
deliberado.

---

## Quando o CI ou o CD falha

A tabela de solução de problemas está em [CI/CD](ci-cd.md#solução-de-problemas).
