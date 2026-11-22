# Relatório de Auditoria e Conformidade de Acesso IAM

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Estratégias de Deploy & Resiliência no Amazon ECS<br>
> **Desafio Ativo:** `02-deploy-rollback-circuit-breaker`<br>
> **Identidade Operacional Auditada:** `AGY-AWS-LAB`<br>
> **ARN:** `arn:aws:iam::123456789012:user/AGY-AWS-LAB`<br>
> **Conta AWS:** `123456789012` (Sanitizada para documentação pública)<br>
> **Região Padrão:** `us-east-2` (Ohio)<br>
> **Data da Auditoria:** 20/11/2026 22:03:00 UTC<br>
> **Perfil AWS CLI:** `agy-aws-lab`<br>
> **Status de Autenticação:** ✅ Autenticado com Sucesso (Sessão Efêmera STS via `aws login` + MFA)<br>

---

## 🎯 1. Modelo de Governança e Autenticação Efêmera

A identidade operacional `AGY-AWS-LAB` segue estritamente o princípio do menor privilégio e o ciclo de vida definido em [iam-access-lifecycle.md](../../docs/iam-access-lifecycle.md):
- **Sem Credenciais Permanentes:** Não existem Access Keys estáticas (`AKIA...`) geradas para este usuário.
- **Sessão Efêmera:** A autenticação é realizada via `aws login --profile agy-aws-lab`, gerando credenciais temporárias no STS protegidas por Multi-Factor Authentication (MFA).
- **Modelo Just-in-Time (JIT):** Políticas com poderes operacionais são anexadas e desanexadas de forma controlada para cada desafio da trilha.

---

## 🔍 2. Reconciliação da Política `AGY-BIA-Desafio2-Deploy-Operacional` e Diagnóstico IAM

Nas auditorias anteriores do projeto, foi formalizada e atribuída ao usuário `AGY-AWS-LAB` a política gerenciada:
- **Nome da Política:** `AGY-BIA-Desafio2-Deploy-Operacional`
- **Permissões Concedidas Declaradas:**
  - `ecs:UpdateService`
  - `ecs:RegisterTaskDefinition`
  - `iam:PassRole` restrito à role `arn:aws:iam::123456789012:role/ecsTaskExecutionRole`

### Limitação de Introspecção via CLI (AuthZ do IAM)
Durante a execução de comandos de inspeção do plano de controle IAM, as seguintes chamadas retornaram erro:

| Operação Testada | Chamada AWS CLI | Código de Retorno | Causa Raiz |
|---|---|:---:|---|
| **Listar Políticas Anexadas** | `aws iam list-attached-user-policies --user-name AGY-AWS-LAB` | `254 (AccessDenied)` | Usuário não possui `iam:ListAttachedUserPolicies`. |
| **Inspecionar Política** | `aws iam get-policy --policy-arn ...` | `254 (AccessDenied)` | Usuário não possui `iam:GetPolicy`. |
| **Listar Grupos do Usuário** | `aws iam list-groups-for-user --user-name AGY-AWS-LAB` | `254 (AccessDenied)` | Usuário não possui `iam:ListGroupsForUser`. |
| **Obter Usuário** | `aws iam get-user` | `254 (AccessDenied)` | Usuário não possui `iam:GetUser`. |

> [!IMPORTANT]
> **Diferenciação Estrita de Governança:**<br>
> A impossibilidade técnica do usuário `AGY-AWS-LAB` em listar ou inspecionar suas próprias políticas no plano de controle do IAM **não significa que as permissões estejam ausentes**. Por regra estrita do laboratório, **não são executadas operações de escrita (deploy/mutação) apenas para testar permissões**.<br>
> Portanto, as permissões de mutação da política `AGY-BIA-Desafio2-Deploy-Operacional` são formalmente categorizadas como **"Ainda não verificadas em execução"**, sendo presumidas como ativas.

---

## 📊 3. Matriz IAM Corrigida: Permissões Comprovadas, Negadas e Pendentes

A classificação abaixo segrega com rigor técnico o estado de cada ação de API:
1. **✅ Comprovada:** Testada empiricamente via API read-only com retorno `0 (Success)`.
2. **❌ Negada (AccessDenied):** Testada empiricamente via API com bloqueio explícito de autorização.
3. **🟡 Ainda Não Verificada:** Não testada nesta etapa por envolver mutação de recursos, mas coberta pela política declarada `AGY-BIA-Desafio2-Deploy-Operacional`.

| Serviço AWS | Ação de API | Tipo / Comando | Classificação de Status | Detalhamento / Evidência |
|---|---|:---:|:---:|---|
| **STS** | `sts:GetCallerIdentity` | Leitura | ✅ **Comprovada** | Identidade confirmada: `AIDAEXAMPLEUSEREXAMPLE`, conta `123456789012`. |
| **ECS** | `ecs:ListClusters` | Leitura | ✅ **Comprovada** | Cluster `cluster-bia-app` listado com sucesso. |
| **ECS** | `ecs:DescribeClusters` | Leitura | ✅ **Comprovada** | Detalhes de capacity providers e estatísticas inspecionados. |
| **ECS** | `ecs:ListServices` | Leitura | ✅ **Comprovada** | 4 serviços do cluster retornados. |
| **ECS** | `ecs:DescribeServices` | Leitura | ✅ **Comprovada** | Deployments, Target Groups e Circuit Breaker auditados. |
| **ECS** | `ecs:ListTaskDefinitions` | Leitura | ✅ **Comprovada** | Lista de famílias e revisões ativas retornada. |
| **ECS** | `ecs:DescribeTaskDefinition`| Leitura | ✅ **Comprovada** | Estrutura completa de `task-def-bia-cloud-app:15` auditada. |
| **ECS** | `ecs:ListTasks` | Leitura | ✅ **Comprovada** | Tarefas listadas com sucesso (retorno `[]`). |
| **ECS** | `ecs:DescribeCapacityProviders` | Leitura | ✅ **Comprovada** | Capacity Provider do ASG inspecionado. |
| **ECS** | `ecs:UpdateService` | Mutação | 🟡 **Ainda Não Verificada** | Declarada em `AGY-BIA-Desafio2-Deploy-Operacional`. Não executada para evitar mutação na fase 0. |
| **ECS** | `ecs:RegisterTaskDefinition` | Mutação | 🟡 **Ainda Não Verificada** | Declarada em `AGY-BIA-Desafio2-Deploy-Operacional`. Não executada na fase 0. |
| **ECS** | `ecs:DeregisterTaskDefinition` | Mutação | 🟡 **Ainda Não Verificada** | Necessária para limpeza pós-teste da revisão de falha. |
| **ECS** | `ecs:ListContainerInstances` | Leitura | ✅ **Comprovada** | Validada via CLI (retornou `[]` sem erros). |
| **ECS** | `ecs:DescribeContainerInstances`| Leitura | 🟡 **Ainda Não Verificada** | Apta a ser testada assim que a instância se registrar no cluster. |
| **IAM** | `iam:PassRole` | Autorização | 🟡 **Ainda Não Verificada** | Declarada em `AGY-BIA-Desafio2-Deploy-Operacional` para `ecsTaskExecutionRole`. |
| **IAM** | `iam:GetRole` | Leitura | ✅ **Comprovada** | Inspecionou trust policy de `ecsTaskExecutionRole` e `role-acesso-ssm`. |
| **IAM** | `iam:ListAttachedUserPolicies` | Leitura | ❌ **Negada (AccessDenied)** | `AccessDenied: no identity-based policy allows action`. |
| **Auto Scaling** | `autoscaling:DescribeAutoScalingGroups` | Leitura | ✅ **Comprovada** | Inspecionou min/max/desired do ASG do cluster. |
| **Auto Scaling** | `autoscaling:SetDesiredCapacity` | Mutação | 🟡 **Ainda Não Verificada** | Concedida pela política `AGY-BIA-Desafio2-ASG-Scale`. A ser executada na Fase 1. |
| **Auto Scaling** | `autoscaling:DescribeScalingActivities` | Leitura | ✅ **Comprovada** | Validada via CLI (histórico de eventos do ASG auditado). |
| **Auto Scaling** | `autoscaling:DescribeAutoScalingInstances` | Leitura | ✅ **Comprovada** | Validada via CLI (retornou `[]` com sucesso). |
| **EC2** | `ec2:DescribeInstances` | Leitura | ✅ **Comprovada** | Detalhou instâncias EC2 da conta. |
| **EC2** | `ec2:DescribeVpcs` | Leitura | ✅ **Comprovada** | VPC padrão identificada (`vpc-093b15ec114bc9eb2`). |
| **EC2** | `ec2:DescribeSubnets` | Leitura | ✅ **Comprovada** | 3 subnets da VPC inspecionadas. |
| **EC2** | `ec2:DescribeSecurityGroups` | Leitura | ✅ **Comprovada** | Security Groups (`bia-alb`, `bia-app`, `bia-cluster`) inspecionados. |
| **EC2** | `ec2:DescribeLaunchTemplates` | Leitura | ✅ **Comprovada** | Validada via CLI (template `lt-0bee60f91f07238b5` inspecionado). |
| **EC2** | `ec2:DescribeLaunchTemplateVersions` | Leitura | ✅ **Comprovada** | Validada via CLI (AMI, `t3.small` e User Data decodificado). |
| **ELB v2** | `elasticloadbalancing:DescribeLoadBalancers` | Leitura | ✅ **Comprovada** | ALB `bia-cloud-alb` inspecionado. |
| **ELB v2** | `elasticloadbalancing:DescribeTargetGroups` | Leitura | ✅ **Comprovada** | Target Groups (`tg-bia-app`, etc.) inspecionados. |
| **ELB v2** | `elasticloadbalancing:DescribeListeners` | Leitura | ✅ **Comprovada** | Listeners das portas 80 e 443 inspecionados. |
| **ELB v2** | `elasticloadbalancing:DescribeTargetHealth` | Leitura | ✅ **Comprovada** | Saúde de alvos consultada com sucesso. |
| **RDS** | `rds:DescribeDBInstances` | Leitura | ✅ **Comprovada** | Status `stopped` de `bia-cloud` confirmado. |
| **ECR** | `ecr:DescribeRepositories` | Leitura | ✅ **Comprovada** | Repositório `bia-cloud-lab` inspecionado. |
| **ECR** | `ecr:DescribeImages` | Leitura | ✅ **Comprovada** | Tags disponíveis verificadas. |
| **CloudWatch Logs** | `logs:DescribeLogGroups` | Leitura | ✅ **Comprovada** | Log group `/ecs/task-def-bia-cloud-app` inspecionado. |
| **CloudWatch Logs** | `logs:DescribeLogStreams` | Leitura | ✅ **Comprovada** | Streams de tarefas inspecionados. |
| **CloudWatch Logs** | `logs:GetLogEvents` | Leitura | ✅ **Comprovada** | Leitura de eventos de log validada. |
| **CloudWatch Alarms**| `cloudwatch:DescribeAlarms` | Leitura | ✅ **Comprovada** | Alarmes de Target Tracking do ASG inspecionados. |
| **SSM** | `ssm:DescribeParameters` / `GetParameter` | Leitura | ❌ **Negada (AccessDenied)** | Desnecessária para a CLI; resolvida pela `ecsTaskExecutionRole`. |

---

## 🗄️ 4. Conclusão sobre a Dependência do Amazon RDS

A revisão do código-fonte Express da BIA em `server.js`, `config/express.js` e `api/controllers/versao.js` estabelece:

1. **Boot Assíncrono Sem Trava de Banco:** O Express inicia ouvindo na porta 8080 (`app.listen`) sem aguardar sincronismo de banco ou executar migrações no boot.
2. **Rota do Target Group (`GET /`):** Serve o index HTML estático compilado da SPA React (`client/build/index.html`).
3. **Rota Oficial da API (`GET /api/versao`):** Retorna imediatamente a resposta `Bia ${process.env.VERSAO_API || "4.2.0"}` sem acionar nenhuma camada de banco ou cache.
4. **Isolamento de Erros:** O Sequelize e o modelo de dados são instanciados sob demanda (*lazy evaluation*) exclusivamente nas rotas de CRUD (`/api/tarefas`).

> [!NOTE]
> **Decisão Final:** **O banco Amazon RDS `bia-cloud` NÃO precisa ser iniciado para o Desafio 02**.<br>
> Ele permanecerá no estado `stopped`, economizando custos e validando com fidelidade o comportamento do ECS Circuit Breaker e os health checks do ALB de forma totalmente isolada.

---

## ⚙️ 5. Permissões Adicionais de Leitura para Acompanhamento do Cluster

Para que o operador consiga acompanhar em tempo real o ciclo de vida das instâncias EC2, a drenagem de containers e as atividades de escalonamento durante o laboratório, recomenda-se a concessão das seguintes ações estritas de leitura:

1. **Acompanhamento de Instâncias de Contêiner no ECS:**
   - `ecs:ListContainerInstances`
   - `ecs:DescribeContainerInstances`
   *(Permite verificar quando a instância EC2 lançada pelo ASG completa o registro no cluster ECS).*

2. **Acompanhamento de Atividades do Auto Scaling:**
   - `autoscaling:DescribeScalingActivities`
   - `autoscaling:DescribeAutoScalingInstances`
   *(Permite auditar os eventos de scale-out e scale-in acionados pelo ASG e checar eventuais falhas de inicialização).*

3. **Auditoria do Launch Template (EC2):**
   - `ec2:DescribeLaunchTemplates`
   - `ec2:DescribeLaunchTemplateVersions`
   *(Permite auditar a versão e configuração do User Data da AMI sem conceder permissão de mutação).*

---

## 📜 6. Política IAM Temporária de Menor Privilégio (Auto Scaling)

A política JSON abaixo atende **exclusivamente** à necessidade de dimensionar o Auto Scaling Group do cluster de forma controlada, aplicando o princípio do menor privilégio com escopo delimitado ao ARN do ASG:

### 6.1. Política de Mutação Mínima: `AGY-BIA-Desafio2-ASG-Scale`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSetDesiredCapacityOnECSClusterASG",
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity"
      ],
      "Resource": "arn:aws:autoscaling:us-east-2:123456789012:autoScalingGroup:*:autoScalingGroupName/Infra-ECS-Cluster-cluster-bia-app-0495f372-ECSAutoScalingGroup-5MzfS0ZZ7Q8j"
    }
  ]
}
```

### 6.2. Política Complementar Recomendada para Telemetria e Diagnóstico: `AGY-BIA-Desafio2-Observability`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECSContainerInstanceObservability",
      "Effect": "Allow",
      "Action": [
        "ecs:ListContainerInstances",
        "ecs:DescribeContainerInstances"
      ],
      "Resource": "arn:aws:ecs:us-east-2:123456789012:cluster/cluster-bia-app"
    },
    {
      "Sid": "AutoScalingActivitiesObservability",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeAutoScalingInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LaunchTemplateAuditReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 🛑 7. Procedimento de Encerramento e Revogação Pós-Laboratório

1. **Redução da Capacidade:** Executar `aws autoscaling set-desired-capacity --desired-capacity 0` para encerrar instâncias EC2 do cluster.
2. **Desanexo das Políticas Temporárias:**<br>
   - Desanexar `AGY-BIA-Desafio2-ASG-Scale`.
   - Se anexada, desanexar `AGY-BIA-Desafio2-Observability`.
3. **Preservação do Repouso:** Garantir que o usuário `AGY-AWS-LAB` retorne ao estado restrito sem privilégios de alteração de capacidade.
