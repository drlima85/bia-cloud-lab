# Scripts Utilitários — Estratégias de Deploy & Resiliência

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Estratégias de Deploy & Resiliência<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Validado Sintaticamente (Não Executado na Nuvem — Ambiente Desprovisionado)<br>
> **Adaptações D2NS:** Versões sanitizadas, defensivas e parametrizadas de deploy, rollback controlado e monitor contínuo de disponibilidade (`check-availability.sh`).

---

## 🎯 Finalidade dos Scripts

Este diretório consolida versões sanitizadas, defensivas e parametrizadas dos utilitários de implantação, reversão e diagnóstico da aplicação BIA no Amazon ECS:

1. **[`deploy.sh`](deploy.sh):** Automação do ciclo de release no Amazon ECS, registrando uma nova revisão da Task Definition com a imagem desejada e aguardando a estabilização do serviço.
2. **[`rollback.sh`](rollback.sh):** Utilitário de reversão controlada que valida a existência prévia da imagem estável no Amazon ECR, clona a Task Definition e comuta o serviço ECS para a versão estável anterior.
3. **[`check-availability.sh`](check-availability.sh):** Monitor contínuo de conectividade e latência HTTP via `curl`, emitindo métricas em tempo real e sumário consolidado com taxa de sucesso de requisições 2XX, 4XX e 5XX.

---

## 🛠️ Dependências Necessárias

Para a execução destes scripts em ambiente local ou pipeline de CI/CD, são necessárias as seguintes ferramentas instaladas e configuradas no `PATH`:

- **Bash:** Versão 4.0 ou superior (suporte a `pipefail` e arrays).
- **AWS CLI:** Versão 2.x configurada com credenciais IAM com permissões mínimas no ECS e ECR.
- **jq:** Utilitário de manipulação de JSON (versão 1.6 ou superior).
- **curl:** Para o monitoramento de disponibilidade e testes HTTP.

---

## 📋 Variáveis de Ambiente e Parâmetros

| Variável | Parâmetro CLI | Valor Padrão | Descrição |
|---|---|---|---|
| `AWS_REGION` | `-r, --region` | `us-east-1` | Região da AWS onde o cluster ECS e repositório ECR residem. |
| `ECR_REPO` | `-e, --ecr-repo` | `bia` | Nome do repositório no Amazon ECR. |
| `ECS_CLUSTER` | `-c, --cluster` | `cluster-bia` | Nome do cluster Amazon ECS. |
| `ECS_SERVICE` | `-s, --service` | `service-bia` | Nome do serviço Amazon ECS. |
| `TASK_FAMILY` | `-f, --task-family` | `task-def-bia` | Família da Task Definition no ECS. |
| `IMAGE_TAG` | `-t, --tag` | `git commit hash` (deploy) | Tag ou commit hash da imagem Docker no ECR. |
| `TARGET_URL` | `-u, --url` | `http://localhost:8080/api/versao` | URL alvo para o monitor de disponibilidade. |
| `INTERVAL_SECONDS` | `-i, --interval` | `2` | Intervalo em segundos entre checagens no monitor. |

---

## 🚀 Exemplos Seguros de Execução

### 1. Deploy Parametrizado (`deploy.sh`)

```bash
# Execução padrão em repositório Git (captura commit hash de 7 caracteres)
./scripts/deploy.sh -r us-east-1 -c cluster-bia -s service-bia

# Deploy com tag explícita
./scripts/deploy.sh -r us-east-1 -c cluster-bia -s service-bia -t v1.2.0
```

### 2. Rollback Controlado (`rollback.sh`)

```bash
# Listar as últimas versões disponíveis no Amazon ECR antes do rollback
./scripts/rollback.sh -r us-east-1 -e bia -l

# Executar rollback para uma tag estável prévia
./scripts/rollback.sh -r us-east-1 -c cluster-bia -s service-bia -t a1b2c3d
```

### 3. Monitoramento de Disponibilidade (`check-availability.sh`)

```bash
# Monitorar endpoint público do ALB a cada 1 segundo
./scripts/check-availability.sh -u http://alb-bia-123456789.us-east-1.elb.amazonaws.com/api/versao -i 1

# Exemplo de saída durante o monitoramento:
# [2026-11-19 15:40:00] Status: 200 | Latência: 45ms | Req #1
# [2026-11-19 15:40:01] Status: 200 | Latência: 43ms | Req #2
# ^C (Ctrl+C encerra e exibe o sumário)
# ==========================================================
#             Sumário de Disponibilidade e Latência
# ==========================================================
# URL Monitorada:       http://alb-bia-123456789.us-east-1.elb.amazonaws.com/api/versao
# Total de Requisições: 120
# Respostas HTTP 2XX:   120
# Respostas HTTP 4XX:   0
# Respostas HTTP 5XX:   0
# Erros de Conexão:     0
# Tempo Médio (ms):     44 ms
# Taxa de Sucesso 2XX:  100%
# ==========================================================
```

---

## 🔍 Limitações Técnicas e Escopo

1. **Não Execução na Nuvem:** Estes scripts foram refinados e validados sintaticamente (`bash -n`), mas **não foram executados na nuvem AWS**, uma vez que a infraestrutura de laboratório do BIA Cloud Lab foi totalmente desprovisionada.
2. **Avaliação Sequencial do Monitor:** O script `check-availability.sh` realiza requisições HTTP sequenciais para acompanhamento em tempo real durante intervenções operacionais. Não substitui ferramentas de teste de estresse de alta concorrência (como k6 ou Artillery).
3. **Preservação dos Originais:** Os scripts operacionais originais localizados na raiz (`deploy-ecs.sh`) e em `scripts/ecs/unix/` foram mantidos intactos para fins de rastreabilidade histórica.
