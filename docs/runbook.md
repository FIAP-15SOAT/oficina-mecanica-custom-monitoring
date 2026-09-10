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
3. **Executar as entregas na ordem de dependência**, cada uma no seu repositório:

   | Ordem | Repositório | Por quê depende do anterior |
   | ---: | --- | --- |
   | 1 | `oficina-mecanica-infra-base` | VPC e subnets |
   | 2 | `oficina-mecanica-database` | precisa da rede |
   | 3 | `oficina-mecanica-k8s` | precisa da rede; publica o listener do NLB |
   | 4 | `oficina-mecanica-app` | precisa do cluster e do banco |
   | 5 | `oficina-mecanica-lambda-customer-auth` | precisa da rede e do banco |
   | 6 | `oficina-mecanica-gateway` | precisa do listener do NLB e da Lambda; **publica `api_endpoint`** |
   | 7 | **`oficina-mecanica-custom-monitoring`** | **precisa de `api_endpoint`** |

4. **Ajustar `ENVIRONMENT_ONLINE` para `true`** nas variables deste repositório.
5. **Executar o CD deste repositório** (`workflow_dispatch`). O resumo da execução publica os quatro endereços
   dos dashboards e o estado do teste sintético — confirme que ele saiu `live`.
6. Conferir, na página do teste sintético, que ele voltou a executar e está verde.

**Se o passo 7 rodar antes do 6**, ele falha com
`This object does not have an attribute named "api_endpoint"`. É o comportamento correto: o repositório está
avisando que o alvo ainda não existe.

---

## Ritual de derrubada do ambiente

1. **Ajustar `ENVIRONMENT_ONLINE` para `false`.**
2. **Executar o CD deste repositório** e confirmar, no resumo, que o teste sintético saiu `paused`.
3. Confirmar na página do teste que **não há novas execuções** depois da entrega.
4. Só então destruir o restante do ambiente, na **ordem inversa** da subida.
5. Encerrar o laboratório.

**Este é o passo esquecido.** Deixar `ENVIRONMENT_ONLINE` em `true` depois de destruir o ambiente reintroduz
exatamente o ruído que o desenho eliminou: o teste continua executando contra um endereço inexistente,
consumindo cota, e o alerta de disponibilidade dispara quatro e-mails para quatro pessoas ao fim de toda sessão. Alguns dias disso e o
time aprende a ignorar todos os alertas — o oposto do objetivo deste repositório.

Dashboards, monitores e configurações de métrica **não** precisam ser destruídos: eles não consomem recurso do
laboratório e não têm custo enquanto não há dado fluindo.

---

## O que fazer quando cada monitor dispara

### Disponibilidade externa · rota pública indisponível · **P1**

A rota `/api/health/ready` falhou em ao menos duas das três localidades por mais de dois minutos.

1. **O ambiente deveria estar no ar?** Se foi derrubado sem ajustar `ENVIRONMENT_ONLINE`, o alerta é falso —
   execute o ritual de derrubada e o incidente acaba aqui.
2. Abra a página do teste sintético: veja **qual** asserção falhou (`statusCode` ou `responseTime`) e em quais
   localidades. Uma só localidade falhando é rede, não aplicação — mas então o monitor não teria disparado.
3. Verifique o grupo **Infra** da Visão Geral: há pods emitindo métrica? Se zero, o problema é o cluster ou o
   deployment, não a aplicação.
4. Verifique o gateway na AWS: o `api_endpoint` mudou? Se sim, o `apply` deste repositório não rodou depois da
   entrega do gateway.
5. Se os pods estão de pé e o endereço está certo, siga para o dashboard de API: latência e erros.

### API · Erros 5xx acima do limite · **P2**

1. Abra o [dashboard de API](dashboards.md#oficina-mecânica--api). A **tabela de rotas** diz se o problema é de
   uma rota ou geral.
2. Grupo **Erros**: o `log_stream` já está filtrado em `status:error`. Leia `@oficina.error.message` e
   `@error.type`.
3. Grupo **Banco**: `pending_requests` subindo indica saturação de pool, que se manifesta como 5xx por tempo
   esgotado.
4. Grupo **Runtime**: `nodejs.eventloop.delay.p99` alto indica bloqueio de event loop.
5. Se o alerta de ordens de serviço disparou junto, o impacto atinge o fluxo de negócio — priorize.

### API · Latência p95 acima do alvo · **P3**

1. **Antes de tratar como incidente, verifique se o limiar é o problema.** Os valores são de percepção de
   usuário, não percentis observados — veja a calibração abaixo.
2. Dashboard de API, grupo **Latência**: o top 10 rotas por p95 diz onde.
3. Grupo **Banco**: a média de `db.client.operation.duration` subiu junto? A causa é o banco.
4. Grupo **Runtime**: event loop e heap.
5. Dashboard de Kubernetes: **estrangulamento de CPU** sustentado explica latência sem explicar erro.

### Ordens de Serviço · Falhas no processamento · **P2**

O mesmo procedimento do alerta de erros 5xx, restrito às rotas de ordem de serviço e orçamento. A diferença é o público: aqui
há impacto de negócio nomeado, e a comunicação para fora do time é diferente.

Se os dois alertas de erro dispararam juntos, é a mesma falha vista de dois ângulos. **Isso é esperado e está documentado**
como redundância assumida.

### Pod · Memória próxima do limite · **P2**

1. Dashboard de Kubernetes, grupo **Memória**: qual pod, e a curva é crescimento contínuo ou pico?
2. **Crescimento contínuo sem platô é vazamento.** Grupo **Runtime** do dashboard de API: `v8js.memory.heap.used`
   acompanha?
3. Em `critical` (90 %), o encerramento por falta de memória é iminente. Se o alerta de reinícios disparar em seguida, ele
   aconteceu.
4. Mitigação imediata: reiniciar o deployment. Correção: investigar o vazamento ou subir o limite no
   repositório `oficina-mecanica-app`.

### Pod · Reinícios de contêiner · **P3**

1. Dashboard de Kubernetes, grupo **Ciclo de vida**: quantos pods e com que frequência.
2. **O alerta de memória disparou antes?** Então foi encerramento por falta de memória.
3. Reinício logo após uma entrega é provavelmente falha de inicialização — verifique os logs do pod.
4. Reinícios repetidos no mesmo pod indicam `CrashLoopBackOff`.
5. Um reinício isolado logo após provisionamento pode ser normal; `new_group_delay` de 600 s existe para
   filtrar a maior parte disso.

### Lambda customer-auth · Erros de execução · **P2**

1. **Qualquer erro aqui é defeito.** A função devolve 401 como resposta normal de credencial inválida; erro de
   plataforma é outra coisa.
2. Visão Geral, grupo **Lambda**: erros contra invocações, e a duração.
3. O link de logs da mensagem já está filtrado em `service:oficina-mecanica-lambda-customer-auth status:error`.
4. Duração próxima do limite de execução ⇒ expiração de prazo. `max_memory_used` próximo de `memorysize` ⇒
   falta de memória. Ambos incrementam `errors`.
5. Sem traces na função (L4): os logs são a única evidência.

### Integrações · Falha de envio de e-mail · **P4**

1. A mensagem nomeia a **categoria** do erro, e ela decide a ação: credencial recusada é configuração, tempo
   esgotado é rede, endereço inválido é dado.
2. P4 significa que isto **não interrompe o fluxo principal**: a ordem de serviço avança, a notificação não sai.
3. O link de logs da mensagem já está filtrado no evento.

### Dependência · Health check degradado · **P3**

1. A mensagem nomeia a **categoria da dependência** que falhou.
2. Se a dependência for o banco, os alertas de erro e de latência provavelmente dispararão em seguida — trate a causa aqui.
3. É o único sinal que nomeia a dependência: a rota de saúde não é observável por métrica nem trace (L3).

---

## Calibração de limiares

Fazer **depois de uma semana com tráfego representativo**, não antes.

### Latência

1. Dashboard de API, grupo **Latência**, janela de 7 dias. Leia o **p95** e o **p99** típicos, ignorando picos
   de provisionamento.
2. Novos limiares: `warning = 2 × p95 observado`, `critical = 4 × p95 observado`.
3. Ajuste `api_latency_p95_warning_seconds` e `api_latency_p95_critical_seconds` em
   `terraform/terraform.tfvars`.
4. **Abra Pull Request citando os valores observados na descrição.** Um limiar sem justificativa registrada é
   um número inventado, e a próxima pessoa não saberá se pode mexer.

### Contagem — erros 5xx, ordens de serviço e envio de e-mail

1. Some os 5xx reais da semana no dashboard de API, por rota.
2. Se algum monitor disparou por falso positivo, suba o limiar. Se um incidente real passou sem alerta,
   desça-o.
3. Mesmas variáveis, mesmo Pull Request com valores na descrição.

### Cota de custom metrics

1. `Organization Settings → Usage → Custom Metrics` na conta.
2. Compare com a estimativa de ~960 em [Observabilidade](observability.md#5-custo-de-custom-metrics) e
   **registre o consumo real lá**.
3. Se a cota apertar, acione a alavanca: remova `http.response.status_code` da lista de tags de
   `http.server.request.duration` em `terraform/metrics.tf`. Isso derruba a estimativa de ~960 para ~160, e
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
