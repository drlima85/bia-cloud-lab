# Relatório de Conformidade e Acesso IAM

> **Projeto:** BIA Cloud Lab — D2NS / Formação AWS<br>
> **Trilha:** `04-deploy-strategies` | **Desafio:** `02-deploy-rollback-circuit-breaker`<br>
> **Identidade Auditada:** `AGY-AWS-LAB` (`arn:aws:iam::123456789012:user/AGY-AWS-LAB`)<br>
> **Perfil CLI:** `agy-aws-lab` | **Região:** `us-east-2`<br>
> **Nota de Sanitização:** O ID da conta AWS foi sanitizado para `123456789012` para publicação em portfólio.

---

## 🎯 1. Modelo de Governança: Autenticação Efêmera e Menor Privilégio

A operação do laboratório segue rigorosamente o princípio do menor privilégio (PoLP) e o ciclo de vida documentado em [iam-access-lifecycle.md](../../docs/iam-access-lifecycle.md):

* **Sem Credenciais Permanentes:** O usuário `AGY-AWS-LAB` não possui Access Keys estáticas (`AKIA...`).
* **Sessão Temporária STS:** Autenticação validada via `aws login --profile agy-aws-lab` com Multi-Factor Authentication (MFA), gerando tokens de curta duração.
* **Segregação de Funções:**
  - `ecsTaskExecutionRole`: Role assumida pelo ECS Agent para pull de imagens no ECR e envio de logs ao CloudWatch.
  - Perfil Operacional: Permissões restritas estritamente aos recursos do cluster `cluster-bia-app` e repositório `bia-cloud-lab`.

---

## 🔍 2. Matriz de Permissões Comprovadas na Nuvem

Durante as fases de auditoria, deploy e reversão, as seguintes ações foram validadas empiricamente:

| Serviço | Ações Comprovadas | Recursos Autorizados | Finalidade no Desafio |
|---|---|---|---|
| **STS** | `sts:GetCallerIdentity` | `*` | Validação *fail-fast* de identidade antes de qualquer operação. |
| **ECS** | `ecs:Describe*`, `ecs:List*`, `ecs:UpdateService`, `ecs:RegisterTaskDefinition` | Cluster `cluster-bia-app`, Família `task-def-bia-cloud-app` | Registro de novas revisões, rollout e monitoramento de estabilização. |
| **ECR** | `ecr:DescribeRepositories`, `ecr:DescribeImages`, `ecr:GetAuthorizationToken` | Repositório `bia-cloud-lab` | Inspeção de tags de imagem e login de container. |
| **Auto Scaling** | `autoscaling:Describe*`, `autoscaling:SetDesiredCapacity` | ASG do Cluster ECS | Controle de capacidade computacional das instâncias `t3.small`. |
| **CloudWatch** | `logs:DescribeLogStreams`, `logs:GetLogEvents` | `/ecs/task-def-bia-cloud-app` | Telemetria e diagnóstico de contêineres em falha. |
| **IAM** | `iam:PassRole` | Role `ecsTaskExecutionRole` | Passagem segura da role de execução para tarefas ECS. |

---

## 🛡️ 3. Diagnóstico de Governança e Lições Aprendidas

Durante a auditoria inicial, comandos de auto-inspeção do IAM (`iam:ListAttachedUserPolicies`, `iam:GetUserPolicy`) retornaram `AccessDeniedException`:

* **Lição de Segurança:** A recusa de introspecção no IAM é uma salvaguarda defensiva legítima. O operador possui as permissões necessárias para atualizar o cluster e as tarefas, mas não tem autorização para ler ou modificar as próprias políticas no IAM, eliminando vetores de reconhecimento interno e escalada de privilégios.
* **Desacoplamento de Segredos:** A leitura de parâmetros sensíveis do SSM Parameter Store (`/bia/db_password`) é executada internamente pelo ECS Agent via `ecsTaskExecutionRole`, sem necessidade de expor credenciais no perfil do operador da CLI.
