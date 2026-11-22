# Guia Operacional de CLI — Amazon ECS

> **Projeto:** BIA Cloud Lab — D2NS / Formação AWS<br>
> **Trilha:** `04-deploy-strategies` | **Desafio:** `02-deploy-rollback-circuit-breaker`<br>
> **Finalidade:** Cheat-Sheet de referência rápida para inspeção, deploy contínuo, rollback e resiliência no Amazon ECS.<br>
> **Nota de Sanitização:** Identificadores utilizam a conta didática `123456789012` e hostnames de exemplo.

---

## 🔑 1. Autenticação e Preparação da Sessão

Todos os comandos AWS CLI devem utilizar explicitamente o perfil e a região do laboratório:

```bash
# 1. Autenticar com credenciais temporárias e MFA:
aws login --profile agy-aws-lab

# 2. Confirmar a identidade STS (fail-fast):
aws sts get-caller-identity --profile agy-aws-lab --region us-east-2
```

---

## 🔍 2. Inspeção Rápida de Recursos (Read-Only)

```bash
# Inspecionar instâncias registradas e tarefas ativas no cluster:
aws ecs describe-clusters --clusters cluster-bia-app \
  --profile agy-aws-lab --region us-east-2 \
  --query "clusters[0].[registeredContainerInstancesCount,runningTasksCount,status]"

# Inspecionar deployments e Circuit Breaker do serviço:
aws ecs describe-services --cluster cluster-bia-app --services service-bia-cloud-app \
  --profile agy-aws-lab --region us-east-2 \
  --query "services[0].[taskDefinition,deployments[].rolloutState,deploymentConfiguration.deploymentCircuitBreaker]"

# Listar as últimas 5 revisões registradas da Task Definition:
aws ecs list-task-definitions --family-prefix task-def-bia-cloud-app \
  --sort DESC --max-items 5 --profile agy-aws-lab --region us-east-2

# Inspecionar saúde dos alvos no Target Group do ALB:
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/tg-bia-app/b17888eb84ac5c03 \
  --profile agy-aws-lab --region us-east-2
```

---

## 🚀 3. Operações de Rollout e Rollback via AWS CLI Nativo

### Atualização de Serviço (Rolling Update):
```bash
aws ecs update-service \
  --cluster cluster-bia-app \
  --service service-bia-cloud-app \
  --task-definition task-def-bia-cloud-app:15 \
  --profile agy-aws-lab \
  --region us-east-2
```

### Acompanhamento e Espera de Estabilização:
```bash
aws ecs wait services-stable \
  --cluster cluster-bia-app \
  --services service-bia-cloud-app \
  --profile agy-aws-lab \
  --region us-east-2
```

### Rollback Direto de Emergência:
```bash
# Comutação imediata para a revisão estável homologada anterior:
aws ecs update-service \
  --cluster cluster-bia-app \
  --service service-bia-cloud-app \
  --task-definition task-def-bia-cloud-app:15 \
  --profile agy-aws-lab \
  --region us-east-2
```

---

## 🛠️ 4. Operações via Suíte Automatizada do Lab

A suíte modular da trilha é acessada via fachada unificada [`deploy-ecs.sh`](../../scripts/deploy-ecs.sh):

| Comando | Operação | Exemplo de Execução |
|---|---|---|
| `list` | Lista revisões reais no ECS com status e tags | `./scripts/deploy-ecs.sh list` |
| `deploy` (Dry-Run) | Simula todo o pipeline sem executar mutações na AWS | `./scripts/deploy-ecs.sh deploy --dry-run` |
| `deploy` (Rápido) | Publica nova Task Def reutilizando imagem do ECR | `./scripts/deploy-ecs.sh deploy --skip-build -t elasticache-v2` |
| `deploy` (Completo) | Docker Build local + ECR Push + Update Service | `./scripts/deploy-ecs.sh deploy` |
| `rollback` (Direto) | Reverte diretamente para revisão estável (bloqueia `:16`) | `./scripts/deploy-ecs.sh rollback -r 15` |
| `check-availability`| Monitora latência e status HTTP do ALB contínuo | `./scripts/deploy-ecs.sh check-availability -i 2` |

---

## 🛑 5. Procedimento de Encerramento (Retorno ao Standby)

Após a realização dos testes, desative a computação para zerar os custos de instâncias EC2:

```bash
# 1. Reduzir tarefas do serviço ECS para zero:
aws ecs update-service --cluster cluster-bia-app --service service-bia-cloud-app \
  --desired-count 0 --profile agy-aws-lab --region us-east-2

# 2. Desligar instâncias do cluster reduzindo o ASG para zero:
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name Infra-ECS-Cluster-cluster-bia-app-0495f372-ECSAutoScalingGroup-5MzfS0ZZ7Q8j \
  --min-size 0 --max-size 0 --desired-capacity 0 --profile agy-aws-lab --region us-east-2
```
