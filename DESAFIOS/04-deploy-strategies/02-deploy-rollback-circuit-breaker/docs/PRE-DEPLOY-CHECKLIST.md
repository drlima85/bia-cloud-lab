# Checklist e Guia Pré-Deploy — Amazon ECS

> **Projeto:** BIA Cloud Lab — D2NS / Formação AWS<br>
> **Trilha:** `04-deploy-strategies` | **Desafio:** `02-deploy-rollback-circuit-breaker`<br>
> **Documento:** `PRE-DEPLOY-CHECKLIST.md`<br>
> **Nota de Sanitização:** Identificadores sensíveis (Conta AWS, endpoints de ALB/RDS) utilizam valores didáticos (`123456789012` e hostnames de exemplo) para conformidade pública.

---

## 📋 1. Checklist Rápido Pré-Deploy

Antes de executar qualquer comando de deploy ou rollback real, valide os seguintes pré-requisitos:

- [ ] **1. Sessão AWS CLI Ativa:** Sessão temporária STS válida obtida via `aws login --profile agy-aws-lab` com MFA concluído.
- [ ] **2. Arquivo `.env` Criado:** Arquivo [`.env`](../../.env.example) gerado a partir do `.env.example` na raiz da trilha (`DESAFIOS/04-deploy-strategies/.env`). Carregado automaticamente pelos scripts.
- [ ] **3. Identidade e Conta Configuradas:** `AWS_ACCOUNT_ID` e `AUTHORIZED_ACCOUNT` preenchidas com os 12 dígitos da sua conta autorizada.
- [ ] **4. Endpoint do ALB Mapeado:** `ENV_APP_ALB_URL` configurada no `.env` apontando para o DNS público do seu Application Load Balancer (`http://<ALB_DNS>/api/versao`).
- [ ] **5. Capacidade Ativada no ASG:** Auto Scaling Group elevado de `0` para **2 instâncias `t3.small`** (`min=2, max=2, desired=2`).
- [ ] **6. Baseline Estável Ativa:** Serviço `service-bia-cloud-app` configurado com `desiredCount = 1` na Task Definition estável `:15`.
- [ ] **7. Escopo de Teste Definido:**
  - *Teste de Infraestrutura ($0/h computação):* RDS permanece `stopped`. O Express inicializa de forma assíncrona e responde `/api/versao` e `/` em memória.
  - *Homologação Funcional Completa:* Requer iniciar a instância RDS `bia-cloud` previamente caso deseje testar a rota `/api/tarefas`.
- [ ] **8. Estratégia de Deploy:** Utilizar `--skip-build -t <TAG>` (ex: `elasticache-v2` ou `rolling-purple-v1`) para reaproveitar imagens do ECR, ou deploy padrão com build Docker local.

---

## 📊 2. Variáveis Obrigatórias no `.env`

Os scripts consomem automaticamente as variáveis do arquivo `DESAFIOS/04-deploy-strategies/.env`:

| Variável | Padrão | Valor a Configurar | Como Validar na AWS CLI | Consequência se Ausente / Incorreta |
|---|---|---|---|---|
| **`AUTHORIZED_ACCOUNT`** / **`AWS_ACCOUNT_ID`** | *Vazio* | 12 dígitos da conta | `aws sts get-caller-identity --query Account --output text` | Bloqueio imediato (*fail-fast*) com `exit 1` antes de qualquer mutação. |
| **`ENV_APP_ALB_URL`** | `http://localhost:8080/api/versao` | `http://<ALB_DNS>/api/versao` | `aws elbv2 describe-load-balancers --names bia-cloud-alb --query "LoadBalancers[0].DNSName"` | Smoke Test pós-deploy falha 5 vezes e aciona auto-rollback de emergência (`exit 3`). |
| **`AWS_PROFILE`** | `agy-aws-lab` | Perfil local configurado | `aws configure list-profiles` | Erro de autenticação STS caso o perfil não exista. |
| **`AWS_REGION`** | `us-east-2` | Região operacional | `aws configure get region` | `ResourceNotFoundException` por apontar para região divergente. |

### Exemplo Mínimo de `.env` (`DESAFIOS/04-deploy-strategies/.env`):
```bash
AWS_ACCOUNT_ID="123456789012"
AUTHORIZED_ACCOUNT="123456789012"
AWS_PROFILE="agy-aws-lab"
AWS_REGION="us-east-2"
ENV_APP_ALB_URL="http://seu-alb-dns.us-east-2.elb.amazonaws.com/api/versao"
```

---

## ⚡ 3. Roteiro Sequencial de Execução

Execute na raiz da trilha (`DESAFIOS/04-deploy-strategies/`):

### Passo 1: Validar Identidade AWS e Leitura do `.env`
```bash
aws sts get-caller-identity --profile agy-aws-lab --region us-east-2
./scripts/deploy-ecs.sh list --dry-run
```

### Passo 2: Reativar Capacidade Computacional Necessária
```bash
# 1. Elevar o ASG para 2 instâncias t3.small
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name Infra-ECS-Cluster-cluster-bia-app-0495f372-ECSAutoScalingGroup-5MzfS0ZZ7Q8j \
  --min-size 2 --max-size 2 --desired-capacity 2 \
  --profile agy-aws-lab --region us-east-2

# 2. Ativar o serviço ECS na baseline estável (Revisão 15)
aws ecs update-service \
  --cluster cluster-bia-app --service service-bia-cloud-app \
  --task-definition task-def-bia-cloud-app:15 --desired-count 1 \
  --profile agy-aws-lab --region us-east-2

# 3. Aguardar estabilização do serviço
aws ecs wait services-stable \
  --cluster cluster-bia-app --services service-bia-cloud-app \
  --profile agy-aws-lab --region us-east-2
```

### Passo 3: Validar a Baseline Estável via HTTP
```bash
curl -i http://<ALB_DNS>/api/versao
# Resposta esperada: HTTP/1.1 200 OK com corpo "Bia 4.2.0"
```

### Passo 4: Simulação Prévia Obrigatória (Dry-Run)
```bash
./scripts/deploy-ecs.sh deploy --dry-run
```

### Passo 5: Executar o Deploy Real
```bash
# Opção A: Deploy rápido reutilizando imagem existente no ECR (sem rebuild local)
./scripts/deploy-ecs.sh deploy --skip-build -t elasticache-v2

# Opção B: Deploy com alternância visual (imagem roxa do Desafio 01)
./scripts/deploy-ecs.sh deploy --skip-build -t rolling-purple-v1

# Opção C: Deploy completo com Docker Build e Push no ECR
./scripts/deploy-ecs.sh deploy
```

### Passo 6: Rollback Controlado (Se necessário)
```bash
./scripts/deploy-ecs.sh rollback -r 15
```

### Passo 7: Encerramento e Retorno ao Standby
```bash
aws ecs update-service --cluster cluster-bia-app --service service-bia-cloud-app --desired-count 0 --profile agy-aws-lab --region us-east-2
aws autoscaling update-auto-scaling-group --auto-scaling-group-name Infra-ECS-Cluster-cluster-bia-app-0495f372-ECSAutoScalingGroup-5MzfS0ZZ7Q8j --min-size 0 --max-size 0 --desired-capacity 0 --profile agy-aws-lab --region us-east-2
```

### 3.4. Governança de Imagens ECR (`--skip-build` e `-t`)

Para acelerar os deploys no laboratório e evitar compilações locais desnecessárias, os scripts suportam a reutilização de imagens pré-existentes no Amazon ECR:

* **Significado de `--skip-build` e `-t <TAG>`:**
  - `--skip-build`: Inibe as etapas locais de `docker build` e `docker push`, buscando a imagem diretamente no repositório ECR.
  - `-t <TAG>`: Especifica a tag mandatória da imagem remota a ser referenciada na nova Task Definition gerada.
* **Relação de `elasticache-v2` com a Baseline :15:**
  - É a imagem estável de referência homologada na Revisão `:15`. Utilizá-la permite validar a substituição saudável de tarefas e o comportamento dos scripts com segurança funcional, sem alterar a interface web.
* **Alternativa `rolling-purple-v1`:**
  - Imagem funcional com cabeçalho roxo (oriunda do Desafio 01), recomendada caso se deseje comprovar visualmente a alternância de versões no navegador sem compilar Docker localmente.

**Exemplo Funcional de Deploy Rápido:**
```bash
./scripts/deploy-ecs.sh deploy --skip-build -t elasticache-v2
```

---

## 🏗️ 4. Dimensionamento do Cluster: Por que 2 instâncias `t3.small`?

A necessidade de 2 instâncias no ASG decorre da política de Rolling Update (`minimumHealthyPercent = 100%`, `maximumPercent = 200%` com `desiredCount = 1`):
- O ECS sobe a nova tarefa **antes** de drenar a anterior. No pico, existem **2 tarefas ativas simultâneas** de 1024 MB cada ($2 \times 1024\text{ MB} = \mathbf{2048\text{ MB}}$).
- A instância `t3.small` tem 2048 MB de RAM física, mas o sistema operacional (AL2023) e o ECS Agent consomem ~135 MB, disponibilizando apenas **1913 MB registráveis**.
- Com 1 nó, $2048\text{ MB} > 1913\text{ MB}$: o deploy trava com o erro `RESOURCE:MEMORY`. Duas instâncias em AZs distintas (`us-east-2a` e `us-east-2b`) são indispensáveis para acomodar a transição com isolamento de rede `awsvpc`.

---

## 💰 5. Estimativa de Custos AWS e Estado dos Recursos

| Recurso | Estado no Laboratório | Estimativa de Custo | Observações de Faturamento |
|---|:---:|:---:|---|
| **EC2 / Tarefas ECS** | Standby (`desired=0`) | **$0.00/h** | Nenhuma instância em execução quando o ASG está zerado. |
| **Amazon RDS** | `stopped` | **$0.00/h** (computação) | A cobrança da instância `db.t3.micro` é suspensa quando parada. |
| **Armazenamento EBS RDS** | Ativo | **~$2.30/mês** | O volume `gp3` de 20 GB continua alocado mesmo com o banco parado. |
| **Auto-Restart RDS** | Mecanismo AWS | Atenção | A AWS religa automaticamente instâncias paradas após 7 dias corridos. |
| **Application Load Balancer** | Provisionado | **~$0.0225/h** (~$16.20/mês) | Taxa básica fixa do ALB mantido para preservar DNS e regras. |
| **Amazon ECR** | Repositório ativo | **~$0.10/GB-mês** | Armazenamento das camadas das imagens publicadas. |

---

## 🛑 6. Troubleshooting Rápido

| Erro Observado | Causa Raiz | Solução Imediata |
|---|---|---|
| `CONFIGURAÇÃO MANDATÓRIA: Nenhuma conta autorizada` | Variáveis `AWS_ACCOUNT_ID` ou `AUTHORIZED_ACCOUNT` não definidas. | Configure sua conta de 12 dígitos no `.env`. |
| `RESOURCE:MEMORY` no cluster / Deploy travado | ASG operando com apenas 1 nó `t3.small` (déficit de 135 MB para 2 tasks). | Eleve o ASG para 2 nós via `aws autoscaling update-auto-scaling-group --min-size 2 --max-size 2 --desired-capacity 2`. |
| `A imagem '...:tag' não foi encontrada no ECR` | O operador utilizou `--skip-build` sem informar `-t`. | Passe explicitamente a tag desejada: `--skip-build -t elasticache-v2`. |
| Smoke Test com código 3 / Auto-rollback disparado | Endpoint `ENV_APP_ALB_URL` inacessível ou Target Group não saudável. | Verifique se a URL do ALB no `.env` possui o DNS correto e confirme a integridade do Target Group. |
