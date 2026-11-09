# IAM — Guia de Acesso: Desafio 5 N8N na AWS

**Conta:** <AWS_ACCOUNT_ID> | **Região:** us-east-2  
**Referência:** `n8n-lab/n8n-ha-single-mode.md` (v1.3)

---

## 1. Arquivos gerados

Todos os arquivos estão em `n8n-lab/iam/`:

| Arquivo | Tipo | Finalidade |
|---|---|---|
| `01-policy-prevalidation-readonly.json` | Política gerenciada | Permissões de leitura para pré-validação. Anexar ao **usuário** `n8n-lab` antes de iniciar. |
| `02-policy-deploy.json` | Política gerenciada | Permissões de escrita para implantação e limpeza. Anexar ao **usuário** `n8n-lab` somente durante o deploy. **Remover depois.** |
| `03-trust-policy-ecs-tasks.json` | Trust policy | Permite que `ecs-tasks.amazonaws.com` assuma a `n8n-task-execution-role`. |
| `04-inline-policy-execution-role.json` | Política inline | Permissões da `n8n-task-execution-role`: SSM secrets + CloudWatch Logs. |
| `05-trust-policy-ec2.json` | Trust policy | Permite que `ec2.amazonaws.com` assuma a `n8n-ec2-instance-role`. |
| `06-instance-role-managed-policies.json` | Guia de referência | ARNs das duas managed policies a anexar à `n8n-ec2-instance-role`. |
| `07-instance-profile.json` | Guia de referência | Comandos para criar o instance profile e associá-lo à role EC2. |

---

## 2. Ordem correta de criação no console IAM

### Fase A — Antes de qualquer recurso AWS (pré-validação)

```
1. Criar política gerenciada  → N8N-Lab-PreValidation-ReadOnly
   Arquivo: 01-policy-prevalidation-readonly.json
   Anexar a: usuário n8n-lab

   (A política N8N-Lab-Infrastructure-ReadOnly já deve estar anexada
    ao usuário desde o inventário inicial.)
```

### Fase B — No início da implantação (Fases 1–2 do plano)

```
2. Criar política gerenciada  → N8N-Lab-Deploy
   Arquivo: 02-policy-deploy.json
   Anexar a: usuário n8n-lab
   ⚠️  REMOVER ao término do laboratório

3. Criar role IAM             → n8n-task-execution-role
   Trust policy: 03-trust-policy-ecs-tasks.json
   Inline policy (nome: n8n-execution-policy): 04-inline-policy-execution-role.json

4. Criar role IAM             → n8n-ec2-instance-role
   Trust policy: 05-trust-policy-ec2.json
   Anexar managed policies (ver 06-instance-role-managed-policies.json):
     - arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
     - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

5. Criar instance profile     → n8n-ec2-instance-profile
   Associar role: n8n-ec2-instance-role
   (ver 07-instance-profile.json)
   ⚠️  O instance profile deve existir ANTES de criar o Launch Template
```

---

## 3. Quem anexa o quê

### Usuário `n8n-lab`

| Política | Quando anexar | Quando remover |
|---|---|---|
| `N8N-Lab-Infrastructure-ReadOnly` | Já aplicada (inventário) | Manter — usada para monitoramento contínuo |
| `N8N-Lab-PreValidation-ReadOnly` | Antes do deploy | Opcional — pode manter para diagnóstico |
| `N8N-Lab-Deploy` | Início do deploy | **Remover após limpeza final** |

### Role `n8n-task-execution-role`

| Política | Tipo | Descrição |
|---|---|---|
| `n8n-execution-policy` | Inline | SSM GetParameters + CloudWatch Logs para /ecs/n8n-ec2 |

### Role `n8n-ec2-instance-role`

| Política | Tipo | ARN |
|---|---|---|
| `AmazonEC2ContainerServiceforEC2Role` | Managed (AWS) | `arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role` |
| `AmazonSSMManagedInstanceCore` | Managed (AWS) | `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` |

---

## 4. Permissões de deploy que devem ser removidas depois

A política `N8N-Lab-Deploy` concede permissões de escrita amplas e **deve ser desanexada do usuário `n8n-lab` após a conclusão do laboratório**. Ela é necessária apenas durante as fases ativas de implantação e limpeza.

Motivo: inclui ações destrutivas como `rds:DeleteDBInstance`, `ecs:DeleteCluster`, `ec2:TerminateInstances`, `autoscaling:DeleteAutoScalingGroup` e `iam:DeleteRole`.

---

## 5. Ações que exigem `Resource: "*"` e por quê

| Ação | Motivo do `*` |
|---|---|
| `ssm:DescribeParameters` | A API SSM não aceita ARN de parâmetro específico como resource nesta operação |
| `ec2:Describe*` em geral | Todas as operações Describe do EC2 ignoram o resource e exigem `*` pela arquitetura da API |
| `ecs:ListContainerInstances`, `ecs:ListTasks`, `ecs:Describe*` | A API ECS aceita `*` mas não filtra por ARN de cluster nessas operações |
| `rds:DescribeOrderableDBInstanceOptions`, `DescribeDBEngineVersions`, `DescribeDBSubnetGroups` | APIs de catálogo RDS — não operam sobre recursos específicos |
| `elasticloadbalancing:Create*`, `Delete*` | ALB/TG/Listener ARNs não são conhecidos antes da criação |
| `autoscaling:Create*`, `Delete*` | ARN do ASG inclui GUID gerado automaticamente |
| `logs:DescribeLogGroups` | Log group ainda não existe no momento da pré-validação |

---

## 6. Dependências e restrições IAM

### Dependências de criação (ordem obrigatória)

```
n8n-task-execution-role  ← deve existir antes de registrar a Task Definition
n8n-ec2-instance-role    ← deve existir antes de criar o Instance Profile
n8n-ec2-instance-profile ← deve existir antes de criar o Launch Template
Launch Template          ← deve existir antes de criar o Auto Scaling Group
Auto Scaling Group       ← deve existir antes de criar o Capacity Provider
```

### Restrição de `iam:PassRole`

A política `N8N-Lab-Deploy` concede `iam:PassRole` restrito a:
```
arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-*
arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/n8n-*
```

Isso significa que o usuário `n8n-lab` **não pode passar** nenhuma role fora do prefixo `n8n-*` para serviços AWS — incluindo a `ecsTaskExecutionRole` do BIA Cloud Lab. Isso é intencional e protege os recursos existentes.

### Proteção ao BIA Cloud Lab

Nenhuma política criada para o Desafio 5 concede acesso a:
- `ecsTaskExecutionRole` (role do BIA)
- `cluster-bia-app` (cluster ECS do BIA)
- `bia-cloud-alb` (ALB do BIA)
- `bia-cloud` (RDS do BIA)
- Qualquer recurso com prefixo diferente de `n8n-*`

---

## 7. Procedimento de limpeza IAM ao final do laboratório

Executar **após** a limpeza completa dos recursos AWS (ver seção 16 do plano):

```bash
# 1. Desanexar managed policies da instance role
aws iam detach-role-policy \
  --role-name n8n-ec2-instance-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role \
  --profile n8n-lab --region us-east-2

aws iam detach-role-policy \
  --role-name n8n-ec2-instance-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --profile n8n-lab --region us-east-2

# 2. Remover role do instance profile e excluir profile
aws iam remove-role-from-instance-profile \
  --instance-profile-name n8n-ec2-instance-profile \
  --role-name n8n-ec2-instance-role \
  --profile n8n-lab --region us-east-2

aws iam delete-instance-profile \
  --instance-profile-name n8n-ec2-instance-profile \
  --profile n8n-lab --region us-east-2

# 3. Excluir instance role
aws iam delete-role \
  --role-name n8n-ec2-instance-role \
  --profile n8n-lab --region us-east-2

# 4. Excluir inline policy da execution role
aws iam delete-role-policy \
  --role-name n8n-task-execution-role \
  --policy-name n8n-execution-policy \
  --profile n8n-lab --region us-east-2

# 5. Excluir execution role
aws iam delete-role \
  --role-name n8n-task-execution-role \
  --profile n8n-lab --region us-east-2

# 6. Desanexar e excluir políticas gerenciadas do usuário n8n-lab
#    (obter ARNs das políticas criadas para o projeto)
aws iam detach-user-policy \
  --user-name n8n-lab \
  --policy-arn <ARN_N8N-Lab-Deploy> \
  --profile n8n-lab --region us-east-2

aws iam detach-user-policy \
  --user-name n8n-lab \
  --policy-arn <ARN_N8N-Lab-PreValidation-ReadOnly> \
  --profile n8n-lab --region us-east-2

aws iam delete-policy --policy-arn <ARN_N8N-Lab-Deploy>
aws iam delete-policy --policy-arn <ARN_N8N-Lab-PreValidation-ReadOnly>
```

> Substituir `<ARN_...>` pelos ARNs reais após criação das políticas. Formato esperado:
> `arn:aws:iam::<AWS_ACCOUNT_ID>:policy/N8N-Lab-Deploy`

---

## 8. Referências rápidas

| Recurso | ARN / Valor |
|---|---|
| Usuário `n8n-lab` | `arn:aws:iam::<AWS_ACCOUNT_ID>:user/n8n-lab` |
| `n8n-task-execution-role` | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-task-execution-role` |
| `n8n-ec2-instance-role` | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-ec2-instance-role` |
| `n8n-ec2-instance-profile` | `arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/n8n-ec2-instance-profile` |
| KMS key `aws/ssm` | `arn:aws:kms:us-east-2:<AWS_ACCOUNT_ID>:key/88a00481-a1aa-4f0d-b686-7777144770cf` |
| Hosted zone Route 53 | `Z0200626TQFMAZ5GPD92` |
| SSM `/n8n/db_password` | `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/db_password` |
| SSM `/n8n/encryption_key` | `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/encryption_key` |
| Log group N8N | `arn:aws:logs:us-east-2:<AWS_ACCOUNT_ID>:log-group:/ecs/n8n-ec2` |
