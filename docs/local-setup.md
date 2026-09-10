# Como executar localmente

O objetivo aqui é **ver o `plan`** antes de abrir um Pull Request. Aplicar localmente é possível, mas não é o
caminho normal — a entrega é da esteira.

---

## Pré-requisitos

| Item | Versão | Para quê |
| --- | --- | --- |
| Terraform | **≥ 1.11.0** | `templatestring` e o piso de versão da solução |
| Credenciais AWS do laboratório | sessão válida | backend S3 e leitura do state do gateway |
| Chave de API do Datadog | — | `provider.api_key` |
| Chave de aplicação do Datadog | service account | `provider.app_key` |

Sem credenciais AWS válidas você ainda consegue rodar `fmt`, `init -backend=false` e `validate` — o que já pega
a maior parte dos erros de sintaxe e de referência.

---

## Passo a passo

```bash
git clone https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring.git
cd oficina-mecanica-custom-monitoring/terraform
```

### 1. Credenciais AWS

Do painel do AWS Academy, copie o bloco de credenciais para `~/.aws/credentials` ou exporte:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_REGION=us-east-1

aws sts get-caller-identity     # confirme antes de seguir
```

Se este comando responder `explicit deny ... voc-cancel-cred`, **a sessão do laboratório expirou**. Renove
antes de continuar.

### 2. Credenciais do Datadog e destinatários

**Nada disso vai para arquivo versionado.** Exporte na sessão:

```bash
export TF_VAR_datadog_api_key=...
export TF_VAR_datadog_app_key=...
export TF_VAR_alert_emails='alguem@exemplo.com,outro@exemplo.com'
export TF_VAR_environment_online=false
```

Confirme as chaves antes de gastar tempo com o Terraform:

```bash
curl -H "DD-API-KEY: $TF_VAR_datadog_api_key" \
     -H "DD-APPLICATION-KEY: $TF_VAR_datadog_app_key" \
     https://api.us5.datadoghq.com/api/v1/validate
# {"valid":true}
```

> **Use os seus próprios endereços em `TF_VAR_alert_emails` ao testar.** Um `plan` não notifica ninguém, mas um
> `apply` acidental reconfiguraria os nove monitores com os destinatários que você exportou.

`terraform.tfvars` já está versionado com todos os valores não sensíveis — identidade, state remoto e os doze
limiares. Não é preciso copiar nada; `terraform.tfvars.example` existe como referência do formato.

### 3. Verificação estrutural, sem credencial nenhuma

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

É exatamente o que o CI faz nos três primeiros passos.

### 4. Prévia contra a conta real

```bash
terraform init -reconfigure
terraform plan
```

Com tudo em ordem e nada a mudar, a saída é `No changes.` — o que significa que a conta está igual ao código.

---

## Como não aplicar sem querer

O risco real é executar `terraform apply` achando que está rodando `plan`. Três hábitos, em ordem de eficácia:

1. **Use `-lock=false` ao rodar `plan`.** Além de evitar disputa com a esteira, é um sinal visual de que a
   intenção é só olhar:
   ```bash
   terraform plan -no-color -lock=false
   ```
2. **Grave o plano e leia antes de qualquer decisão:**
   ```bash
   terraform plan -out=tfplan
   terraform show tfplan | less
   ```
3. **Nunca use `-auto-approve` localmente.** Ele existe só no CD, onde a revisão aconteceu no Pull Request.

Se você **precisar** aplicar localmente — tipicamente para desbloquear uma sessão de laboratório fora do
horário da esteira:

- Confirme que está na `main` atualizada: aplicar de uma branch de trabalho grava no state compartilhado uma
  configuração que ainda não foi revisada.
- Confirme `TF_VAR_environment_online` com o valor **correto para o estado atual do ambiente**.
- Avise o time, porque o state é compartilhado e a trava fará a esteira falhar enquanto você estiver aplicando.

---

## Consultar a conta sem passar pelo Terraform

Para confirmar um nome de métrica ou uma faceta antes de escrever a consulta — que é o que
[Convenções](conventions.md) exige na revisão:

```bash
# métricas ativas nos últimos 30 dias
curl -s -H "DD-API-KEY: $TF_VAR_datadog_api_key" -H "DD-APPLICATION-KEY: $TF_VAR_datadog_app_key" \
  "https://api.us5.datadoghq.com/api/v1/metrics?from=$(( $(date +%s) - 2592000 ))"

# uma consulta de métrica, com dados
curl -s -G -H "DD-API-KEY: $TF_VAR_datadog_api_key" -H "DD-APPLICATION-KEY: $TF_VAR_datadog_app_key" \
  --data-urlencode "from=$(( $(date +%s) - 86400 ))" --data-urlencode "to=$(date +%s)" \
  --data-urlencode "query=count:http.server.request.duration{env:production,service:oficina-mecanica-api} by {http.route}" \
  "https://api.us5.datadoghq.com/api/v1/query"

# valores de uma faceta de log
curl -s -X POST -H "DD-API-KEY: $TF_VAR_datadog_api_key" -H "DD-APPLICATION-KEY: $TF_VAR_datadog_app_key" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"query":"service:oficina-mecanica-api","from":"now-30d","to":"now"},
       "compute":[{"aggregation":"count","type":"total"}],
       "group_by":[{"facet":"@oficina.event.name","limit":50}]}' \
  "https://api.us5.datadoghq.com/api/v2/logs/analytics/aggregate"

# validar uma consulta de alerta antes de escrever HCL
curl -s -X POST -H "DD-API-KEY: $TF_VAR_datadog_api_key" -H "DD-APPLICATION-KEY: $TF_VAR_datadog_app_key" \
  -H "Content-Type: application/json" \
  -d '{"name":"validacao","type":"query alert","message":"x",
       "query":"sum(last_10m):count:http.server.request.duration{env:production} by {http.route}.as_count() > 20",
       "options":{"thresholds":{"critical":20}}}' \
  "https://api.us5.datadoghq.com/api/v1/monitor/validate"
```

As duas primeiras exigem o escopo `timeseries_query`; a terceira, `logs_read_data`. Se responderem
`403 Forbidden`, a chave não os tem — ver [CI/CD](ci-cd.md#como-obter-a-credencial-do-destino-de-telemetria).

Os `group_by` do endpoint de agregação de logs **não aceitam o campo `sort` com `aggregation`**: incluí-lo
devolve `400 input_validation_error`. Omita-o.

---

## Problemas frequentes

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `explicit deny ... voc-cancel-cred` | Sessão do laboratório expirada | Renovar as credenciais no AWS Academy |
| `Backend initialization required` | Backend ainda não configurado nesta cópia | `terraform init -reconfigure` |
| `This object does not have an attribute named "api_endpoint"` | Gateway destruído: state vazio | Subir o gateway antes, ou aceitar que o teste sintético não pode ser planejado |
| `missing_aggregation :: AGG_AVG/AGG_P95` | Configuração de tags da métrica ainda não aplicada | Esperado antes do primeiro `apply` |
| `Error acquiring the state lock` | A esteira está aplicando | Aguardar |
| `terraform console` reclama do backend | `console` também precisa do backend inicializado | `terraform init -reconfigure` antes |
