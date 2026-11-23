# Inventário Técnico de Infraestrutura AWS — Desafio 02

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Estratégias de Deploy & Resiliência no Amazon ECS<br>
> **Desafio Ativo:** `02-deploy-rollback-circuit-breaker`<br>
> **Data da Coleta:** 20/11/2026 21:55:00 UTC<br>
> **Conta AWS:** `123456789012` (Sanitizada para documentação pública)<br>
> **Região Operacional:** `us-east-2` (Ohio)<br>
> **Identidade Operacional:** `arn:aws:iam::123456789012:user/AGY-AWS-LAB`<br>
> **Perfil AWS CLI:** `agy-aws-lab`<br>
> **Status de Autenticação:** ✅ Autenticado com MFA / Credenciais Efêmeras STS<br>
> **Modo de Coleta:** Somente Leitura (Read-Only) — Nenhuma mutação executada<br>

---

## 🎯 1. Resumo Executivo do Estado Atual

O ambiente do laboratório encontra-se em **estado de repouso planejado (standby/desligado)** para otimização de custos:
- O cluster ECS está ativo, porém com `desiredCount = 0` e `registeredContainerInstancesCount = 0`.
- O Auto Scaling Group está configurado com capacidade desejada `0` (nenhuma instância EC2 ativa no cluster).
- O banco de dados relacional Amazon RDS (`bia-cloud`) está no estado **`stopped`**.
- O cluster ElastiCache não possui nós ou clusters ativos.
- O Application Load Balancer (`bia-cloud-alb`) permanece provisionado e ativo, porém sem alvos saudáveis registrados (`TargetHealthDescriptions: []`).
- O repositório ECR (`bia-cloud-lab`) contém imagens estáveis armazenadas e prontas para uso.

---

## 🏗️ 2. Amazon ECS (Elastic Container Service)

### 2.1. Cluster ECS

| Atributo | Valor Observado via AWS CLI |
|---|---|
| **Cluster Name** | `cluster-bia-app` |
| **Cluster ARN** | `arn:aws:ecs:us-east-2:123456789012:cluster/cluster-bia-app` |
| **Status** | `ACTIVE` |
| **Instâncias de Container Registradas** | `2` (`i-082efe6b1acd844a1`, `i-0c1271a67f553628a` em us-east-2a) |
| **Tarefas em Execução (Running Tasks)** | `1` (`397d23288bdb4847967b137b290ce734` - revisão 15 estável) |
| **Tarefas Pendentes (Pending Tasks)** | `0` |
| **Serviços Ativos** | `4` (`service-bia-cloud-app`, `service-bia-cloud-alb`, `service-bia-cloud-ru`, `service-bia-cloud-bluegreen`) |
| **Capacity Providers Vinculados** | `FARGATE`, `FARGATE_SPOT`, `Infra-ECS-Cluster-cluster-bia-app-0495f372-AsgCapacityProvider-mJfUexFrKWNd` |
| **Estratégia Padrão de Capacity Provider** | `Infra-ECS-Cluster-cluster-bia-app-0495f372-AsgCapacityProvider-mJfUexFrKWNd` (Weight: 1, Base: 0) |
| **Container Insights** | `disabled` |
| **Stack CloudFormation de Origem** | `Infra-ECS-Cluster-cluster-bia-app-0495f372` |

### 2.2. Serviço Principal em Foco: `service-bia-cloud-app`

| Parâmetro | Configuração Atual no ECS | Observação / Requisito Desafio 02 |
|---|---|---|
| **Service Name** | `service-bia-cloud-app` | Serviço alvo para o teste do Circuit Breaker |
| **Launch Type** | `EC2` | Execução em instâncias EC2 gerenciadas via ASG |
| **Desired Count** | `1` | Réplica ativa baseline para teste de resiliência |
| **Task Definition Ativa** | `task-def-bia-cloud-app:15` | Última revisão operacional registrada |
| **Circuit Breaker Atual** | `enable: true`, `rollback: true` | ✅ **Ativado com sucesso na Fase 1** |
| **Minimum Healthy Percent** | `100%` | Garante atendimento ininterrupto durante deploy |
| **Maximum Percent** | `200%` | Permite provisionar nova tarefa antes de drenar anterior |
| **Deployment Strategy** | `ROLLING` | Padrão rolling update nativo do ECS |
| **Target Group Vinculado** | `arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/tg-bia-app/b17888eb84ac5c03` | Porta 8080 do contêiner `bia-cloud-app` |
| **Subnets Configuradas** | `subnet-0c9a226c460d77c8f`, `subnet-0aef2d36da47e89e9` | Subnets em us-east-2b e us-east-2a |
| **Security Groups** | `bia-app` | Permite tráfego originado no Security Group do ALB (`bia-alb`) |
| **Health Check Grace Period** | `0` segundos | Recomendado parametrizar `60` segundos |
| **Enable Execute Command** | `false` | Acesso interativo desativado |

### 2.3. Outros Serviços ECS Registrados no Cluster

- **`service-bia-cloud-alb`:** Status `ACTIVE`, Desired: 0, Task Def: `task-def-bia-cloud-alb:2`.
- **`service-bia-cloud-ru`:** Status `ACTIVE`, Desired: 0, Task Def: `task-def-bia-cloud-ru:3`.
- **`service-bia-cloud-bluegreen`:** Status `ACTIVE`, Desired: 0, Task Def: `task-def-bia-cloud-bg:3`.

### 2.4. Task Definitions Registradas

Famílias e revisões ativas encontradas na conta:
- `task-def-bia-cloud-app`: revisões `9`, `10`, `11`, `12`, `13`, `14`, `15` (estável primária), `16` (falha induzida para teste de Circuit Breaker).
- `task-def-bia-cloud-alb`: revisões `1`, `2`.
- `task-def-bia-cloud-bg`: revisões `1`, `2`, `3`.
- `task-def-bia-cloud-ru`: revisões `1`, `2`, `3`.

**Detalhamento da Revisão Ativa (`task-def-bia-cloud-app:15`):**
- **Family:** `task-def-bia-cloud-app`
- **Network Mode:** `awsvpc`
- **CPU / Memory da Task:** `1024` / `1024`
- **Execution Role:** `arn:aws:iam::123456789012:role/ecsTaskExecutionRole`
- **Task Role:** Não configurada
- **Container Name:** `bia-cloud-app`
- **Imagem:** `123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:elasticache-v2`
- **Port Mapping:** Host 8080 $\to$ Container 8080 (TCP, HTTP)
- **Log Driver:** `awslogs` apontando para `/ecs/task-def-bia-cloud-app` na região `us-east-2`

---

## ⚙️ 3. Capacity Provider, Auto Scaling Group & Launch Template

### 3.1. ECS Capacity Provider

| Atributo | Valor Observado |
|---|---|
| **Capacity Provider Name** | `Infra-ECS-Cluster-cluster-bia-app-0495f372-AsgCapacityProvider-mJfUexFrKWNd` |
| **Status** | `ACTIVE` |
| **Tipo** | `EC2_AUTOSCALING` |
| **Auto Scaling Group Vinculado** | `Infra-ECS-Cluster-cluster-bia-app-0495f372-ECSAutoScalingGroup-5MzfS0ZZ7Q8j` |
| **Managed Scaling** | `ENABLED` |
| **Target Capacity** | `100%` |
| **Minimum Scaling Step Size** | `1` |
| **Maximum Scaling Step Size** | `10000` |
| **Instance Warmup Period** | `300` segundos |
| **Managed Draining** | `ENABLED` (Hook: `ecs-managed-draining-termination-hook`) |
| **Managed Termination Protection** | `DISABLED` |

### 3.2. Auto Scaling Group (ASG)

| Atributo | Valor Observado |
|---|---|
| **ASG Name** | `Infra-ECS-Cluster-cluster-bia-app-0495f372-ECSAutoScalingGroup-5MzfS0ZZ7Q8j` |
| **Min Size** | `0` |
| **Max Size** | `2` |
| **Desired Capacity** | `2` (dimensionamento para permitir deployment com maxPercent 200%) |
| **Instâncias Ativas** | `i-082efe6b1acd844a1`, `i-0c1271a67f553628a` (ambas `InService` e `Healthy`) |
| **Availability Zones** | `us-east-2a`, `us-east-2b` |
| **Subnets Vinculadas** | `subnet-0c9a226c460d77c8f`, `subnet-0aef2d36da47e89e9` |
| **Health Check Type** | `EC2` |
| **Launch Template Vinculado** | `ECSLaunchTemplate_46ekIKEeI83p` (`lt-0bee60f91f07238b5`), Versão `1` |
| **Scaling Policy Ativa** | `ECSManagedAutoScalingPolicy-8dc7507f-d47f-4284-853a-61efe4ef119b` |

### 3.3. Launch Template

| Atributo | Valor Observado via AWS CLI |
|---|---|
| **Launch Template ID** | `lt-0bee60f91f07238b5` |
| **Launch Template Name** | `ECSLaunchTemplate_46ekIKEeI83p` |
| **Versão Padrão / Mais Recente** | `1` / `1` |
| **AMI ID** | `ami-030831d5502ebf96d` (Amazon Linux 2023 ECS-optimized x86_64) |
| **Instance Type** | `t3.small` |
| **IAM Instance Profile** | `arn:aws:iam::123456789012:instance-profile/ecsInstanceRole` |
| **Security Groups** | `bia-cluster` |
| **User Data (Decodificado)** | `#!/bin/bash \necho ECS_CLUSTER=cluster-bia-app >> /etc/ecs/ecs.config;` |
| **Status de Verificação via CLI** | ✅ **Comprovado com Sucesso** (Permissões de leitura liberadas e auditadas) |

---

## 🌐 4. EC2, Application Load Balancer & Target Groups

### 4.1. Instâncias EC2 do Cluster ECS

| Instance ID | Papel / Função | Tipo | Subnet / AZ | Status Operacional | Observação |
|---|---|---|---|---|---|
| `i-082efe6b1acd844a1` | Container Instance do Cluster | `t3.small` | `subnet-0aef2d36da47e89e9` (AZ 2a) | `InService` / Ativa no teste | Instância gerenciada pelo ASG para hospedar tarefas do serviço ECS |
| `i-0c1271a67f553628a` | Container Instance do Cluster | `t3.small` | `subnet-0c9a226c460d77c8f` (AZ 2b) | `InService` / Ativa no teste | Instância gerenciada pelo ASG para hospedar tarefas do serviço ECS |

### 4.2. Application Load Balancer (ALB)

| Atributo | Valor Observado via AWS CLI |
|---|---|
| **Nome** | `bia-cloud-alb` |
| **ARN** | `arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/bia-cloud-alb/01de9ce7bd7c2119` |
| **DNS Name** | `bia-cloud-alb-1234567890.us-east-2.elb.amazonaws.com` |
| **Status** | `active` |
| **Scheme** | `internet-facing` |
| **VPC** | `vpc-093b15ec114bc9eb2` |
| **Zonas de Disponibilidade** | `us-east-2a` (`subnet-0aef2d36da47e89e9`), `us-east-2b` (`subnet-0c9a226c460d77c8f`) |
| **Security Group do ALB** | `bia-alb` |

### 4.3. Target Groups do ALB

| Target Group | Porta / Protocolo | Target Type | Health Check Path | Intervalo / Timeout | Matcher | Status Alvos |
|---|---|---|---|---|---|---|
| **`tg-bia-app`** | 80 / HTTP | `ip` | `/` | 30s / 5s | 200 | `1 target healthy` (`172.31.11.83:8080`) |
| **`tg-bia-app-ru`** | 80 / HTTP | `ip` | `/` | 30s / 5s | 200 | `TargetHealthDescriptions: []` (sem alvos) |
| **`tg-bia-bg-blue`** | 8080 / HTTP | `ip` | `/` | 30s / 5s | 200 | `TargetHealthDescriptions: []` (sem alvos) |
| **`tg-bia-bg-green`** | 8080 / HTTP | `ip` | `/` | 30s / 5s | 200 | `TargetHealthDescriptions: []` (sem alvos) |

> [!NOTE]
> Conforme registrado no [ADR 05](../../docs/architecture-decisions.md#adr-05-adoção-da-rota-apiversao-para-health-checks-da-aplicação), a rota oficial de health check de backend da BIA é `/api/versao`. O Target Group atual está configurado com `/`, que responde à raiz do frontend web SPA.

### 4.4. Listeners do ALB

1. **Porta 80 (HTTP):**
   - Ação padrão: Forward 100% do tráfego para `tg-bia-app` (`arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/tg-bia-app/b17888eb84ac5c03`).
2. **Porta 443 (HTTPS):**
   - Certificado ACM: `arn:aws:acm:us-east-2:123456789012:certificate/56a03714-9967-4655-b162-d4badfd3445a`
   - Ação padrão: Forward ponderado — `tg-bia-app` (Peso: 1) e `tg-bia-app-ru` (Peso: 0).

---

## 🔒 5. Topologia de Rede & Grupos de Segurança

### 5.1. Virtual Private Cloud (VPC) & Subnets

- **VPC Padrão:** `vpc-093b15ec114bc9eb2` (Bloco CIDR: `172.31.0.0/16`, Status: `available`).
- **Subnets Públicas:**
  - `subnet-0aef2d36da47e89e9`: us-east-2a (`172.31.0.0/20`), IP disponíveis: 4089.
  - `subnet-0c9a226c460d77c8f`: us-east-2b (`172.31.16.0/20`), IP disponíveis: 4090.
  - `subnet-01913249f938d6a71`: us-east-2c (`172.31.32.0/20`), IP disponíveis: 4091.

### 5.2. Security Groups Relevantes

| Grupo de Segurança | Finalidade Arquitetural | Regras de Inbound Relevantes |
|---|---|---|
| `bia-alb` | Entrada externa do ALB | Portas 80 e 443 liberadas para internet (`0.0.0.0/0`) |
| `bia-app` | Tarefas ECS (`awsvpc`) | Permite portas TCP da aplicação originadas de `bia-alb` |
| `bia-cluster` | Instâncias EC2 do ASG | Tráfego de gerenciamento do cluster ECS |
| `rds-sg` (*RDS SG*) | Banco PostgreSQL RDS | Permite porta 5432 vinda de instâncias e tarefas BIA |
| `bia-cache` | Cache ElastiCache / Valkey | Permite porta 6379 originada de `bia-app` |
| `default` | Grupo padrão da VPC | Portas 8080 e 6379 com acessos locais cruzados |

---

## 🗄️ 6. Recursos Compartilhados, Dados & Telemetria

### 6.1. Amazon RDS (Banco de Dados Relacional)

| Parâmetro | Valor Observado via AWS CLI |
|---|---|
| **DB Instance Identifier** | `bia-cloud` |
| **Engine / Versão** | PostgreSQL 18.3 |
| **Instance Class** | `db.t3.micro` (Single-AZ, gp3 20 GB) |
| **Status Atual** | `stopped` (Parado para economia de recursos) |
| **Endpoint** | `bia-cloud.c12345678901.us-east-2.rds.amazonaws.com:5432` |
| **Master Username** | `postgres` |
| **Alocação de Storage** | 20 GB |
| **Deletion Protection** | `true` |
| **Data Prevista de Auto-Restart** | `24/11/2026 04:03:46 UTC` (mecanismo automático da AWS de religamento a cada 7 dias) |

> [!NOTE]
> **Auditoria de Código e Independência do RDS no Desafio 02:**<br>
> A auditoria do código-fonte Express da BIA (`server.js`, `config/express.js`, `api/controllers/versao.js`) comprovou que:
> 1. O servidor HTTP sobe de forma assíncrona **sem bloqueio ou handshake síncrono de inicialização** com o PostgreSQL.
> 2. A rota do Target Group (`/`) serve o frontend estático React SPA (`client/build/index.html`).
> 3. A rota oficial de versão da API (`/api/versao`) retorna diretamente a string de versão em memória sem consultar o banco de dados.
> 4. As conexões Sequelize com o banco operam em modelo *lazy-loading*, restritas aos endpoints de negócio (`/api/tarefas`).
>
> **Decisão Operacional:** O banco RDS `bia-cloud` **permanecerá no estado `stopped`** durante todo o Desafio 02, eliminando custos de banco e comprovando o desacoplamento de resiliência dos health checks de infraestrutura.

### 6.2. Amazon ElastiCache

- **Clusters Ativos (`describe-cache-clusters`):** `[]` (nenhum cluster em execução).
- **Replication Groups (`describe-replication-groups`):** `[]` (nenhum grupo de replicação em execução).
- **Status:** Desprovisionado para otimização de custos de laboratório. A aplicação opera com fallback local caso o cache não responda ou as chamadas de inicialização contornem a ausência de nós.

### 6.3. Amazon ECR (Elastic Container Registry)

- **Repositório:** `bia-cloud-lab`
- **URI:** `123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab`
- **Tags Disponíveis:**
  - `elasticache-v2` (imagem base da Task Definition `:15`)
  - `rolling-purple-v1` (imagem alternativa para validação de alteração visual)
  - `elasticache-v1`
  - `4.2.0`

### 6.4. AWS Systems Manager Parameter Store

- **Parâmetro de Referência:** `/bia/db_password` (referenciado nas Task Definitions sanitizadas via `secrets`).
- **Status de Acesso via CLI para AGY-AWS-LAB:** ⚠️ `AccessDeniedException` ao tentar `ssm:DescribeParameters` e `ssm:GetParameter`. A leitura do parâmetro em runtime é realizada pela role `ecsTaskExecutionRole` do ECS agent, não sendo necessária para o usuário da CLI a menos que solicitada inspeção explícita de valor.

### 6.5. Amazon CloudWatch Logs & Alarms

- **Log Groups Ativos:**
  - `/ecs/task-def-bia-cloud-app` (retenção padrão, log streams com logs históricos de tarefas anteriores).
  - `/ecs/task-def-bia-cloud-alb` (retenção de 7 dias).
  - `/ecs/task-def-bia-cloud-cache`.
- **CloudWatch Alarms:**
  - `TargetTracking-Infra-ECS-Cluster-cluster-bia-app-...-AlarmHigh`: Alarme de auto scaling para capacidade gerenciada (Estado: `OK`).
  - `TargetTracking-Infra-ECS-Cluster-cluster-bia-app-...-AlarmLow`: Alarme de escala para redução de capacidade (Estado: `OK`).

### 6.6. IAM Roles Especializadas Observadas

- **`ecsTaskExecutionRole`:**
  - ARN: `arn:aws:iam::123456789012:role/ecsTaskExecutionRole`
  - Trust Policy: `ecs-tasks.amazonaws.com`
  - Utilizada pelo ECS Agent para pull de imagens no ECR e envio de logs ao CloudWatch.
- **`ecsInstanceRole`:**
  - ARN: `arn:aws:iam::123456789012:role/ecsInstanceRole`
  - Trust Policy: `ec2.amazonaws.com`
  - Utilizada pelas instâncias EC2 do Auto Scaling Group para registro de nós no cluster ECS e comunicação com o plano de controle.
