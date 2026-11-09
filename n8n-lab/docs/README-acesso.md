# IAM — Guia de Acesso: Desafio 5 N8N na AWS

**Conta:** <AWS_ACCOUNT_ID> | **Região:** us-east-2  
**Referência de planejamento:** `n8n-lab/n8n-ha-single-mode.md` (v1.3)  
**Data:** 2026-11-07

---

## 1. Arquivos gerados

Localização: `n8n-lab/iam/`

| # | Arquivo | Tipo | Destinatário |
|---|---|---|---|
| 01 | `01-policy-prevalidation-readonly.json` | Política gerenciada (somente leitura) | Usuário `n8n-lab` |
| 02 | `02-policy-deploy.json` | Política gerenciada (escrita — temporária) | Usuário `n8n-lab` |
| 03 | `03-trust-policy-ecs-tasks.json` | Trust policy | Role `n8n-task-execution-role` |
| 04 | `04-inline-policy-execution-role.json` | Política inline | Role `n8n-task-execution-role` |
| 05 | `05-trust-policy-ec2.json` | Trust policy | Role `n8n-ec2-instance-role` |
| 06 | `06-instance-role-managed-policies.json` | Guia de referência | Role `n8n-ec2-instance-role` |
| 07 | `07-instance-profile.json` | Guia de referência | Instance Profile `n8n-ec2-instance-profile` |

### Finalidade de cada arquivo

**`01-policy-prevalidation-readonly.json`**  
Habilita o usuário `n8n-lab` a executar as verificações de pré-implantação: consultar AMI ECS, versões do Postgres, subnet groups do RDS, launch templates, roles criadas, log groups e a chave KMS. Nenhuma ação de escrita.

**`02-policy-deploy.json`**  
Habilita o usuário `n8n-lab` a criar, configurar, validar e excluir todos os recursos do Desafio 5: Security Groups, Launch Template, Auto Scaling Group, ECS Cluster/Service/Task Definition, ALB, Target Group, RDS, parâmetros SSM, roles IAM, registro DNS e log group. **Política temporária — remover após a limpeza final.**

**`03-trust-policy-ecs-tasks.json`**  
Define que o serviço `ecs-tasks.amazonaws.com` pode assumir a `n8n-task-execution-role`. Usada ao criar a role no console ou via CLI.

**`04-inline-policy-execution-role.json`**  
Permissões da `n8n-task-execution-role`, usada pelo ECS Agent (no plano da instância EC2) para: (a) buscar os segredos SSM antes de iniciar o container e (b) entregar logs ao CloudWatch via Docker daemon. O container em runtime **não** usa esta role.

**`05-trust-policy-ec2.json`**  
Define que o serviço `ec2.amazonaws.com` pode assumir a `n8n-ec2-instance-role`. Usada ao criar a role.

**`06-instance-role-managed-policies.json`**  
Guia de referência com os ARNs das duas managed policies da AWS a anexar à `n8n-ec2-instance-role` e os comandos CLI correspondentes.

**`07-instance-profile.json`**  
Guia de referência com os comandos para criar o `n8n-ec2-instance-profile`, associar a `n8n-ec2-instance-role` e o ARN esperado para uso no Launch Template.

---

## 2. Ordem correta de criação e configuração no console IAM

### ETAPA A — Antes de qualquer recurso AWS

```
Pré-requisito: N8N-Lab-Infrastructure-ReadOnly já deve estar
               anexada ao usuário n8n-lab (inventário inicial).

1. Criar política gerenciada: N8N-Lab-PreValidation-ReadOnly
   Arquivo: 01-policy-prevalidation-readonly.json
   Console: IAM → Policies → Create policy → JSON → colar conteúdo
   Depois: Attach ao usuário n8n-lab
```

### ETAPA B — Início da implantação (Fase 2 do plano)

```
2. Criar política gerenciada: N8N-Lab-Deploy
   Arquivo: 02-policy-deploy.json
   Console: IAM → Policies → Create policy → JSON → colar conteúdo
   Depois: Attach ao usuário n8n-lab
   ⚠️  TEMPORÁRIA — remover após a limpeza final

3. Criar role: n8n-task-execution-role
   Console: IAM → Roles → Create role
     Trusted entity: AWS service → Elastic Container Service Task
     Pular managed policies (adicionaremos inline)
     Role name: n8n-task-execution-role
   Alternativa (trust policy customizada):
     Trusted entity: Custom trust policy
     Arquivo: 03-trust-policy-ecs-tasks.json
   Após criar a role:
     → Add inline policy (nome: n8n-execution-policy)
     → Arquivo: 04-inline-policy-execution-role.json

4. Criar role: n8n-ec2-instance-role
   Console: IAM → Roles → Create role
     Trusted entity: AWS service → EC2
     Attach managed policies:
       - AmazonEC2ContainerServiceforEC2Role
       - AmazonSSMManagedInstanceCore
     Role name: n8n-ec2-instance-role
   Arquivo de referência: 05-trust-policy-ec2.json (trust policy)
   Arquivo de referência: 06-instance-role-managed-policies.json (ARNs)

5. Criar instance profile: n8n-ec2-instance-profile
   Nota: ao criar a role via console com tipo EC2, o instance profile
         é criado automaticamente com o mesmo nome da role.
   Se criando via CLI (ver 07-instance-profile.json):
     aws iam create-instance-profile --instance-profile-name n8n-ec2-instance-profile
     aws iam add-role-to-instance-profile \
       --instance-profile-name n8n-ec2-instance-profile \
       --role-name n8n-ec2-instance-role
   ⚠️  O instance profile deve existir ANTES de criar o Launch Template
```

---

## 3. O que é anexado a quem

### Usuário `n8n-lab` (políticas gerenciadas)

| Política | Temporária? | Quando |
|---|---|---|
| `N8N-Lab-Infrastructure-ReadOnly` | Não | Já aplicada — manter |
| `N8N-Lab-PreValidation-ReadOnly` | Não | Antes do deploy — pode manter |
| `N8N-Lab-Deploy` | **Sim** | Só durante implantação e limpeza |

### Role `n8n-task-execution-role` (inline policy)

| Política | Nome | Tipo |
|---|---|---|
| Arquivo `04` | `n8n-execution-policy` | Inline |

### Role `n8n-ec2-instance-role` (managed policies)

| Política | ARN |
|---|---|
| `AmazonEC2ContainerServiceforEC2Role` | `arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role` |
| `AmazonSSMManagedInstanceCore` | `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` |

---

## 4. Permissões temporárias que podem ser removidas após a implantação

### `N8N-Lab-Deploy` — desanexar do usuário `n8n-lab` após limpeza final

Esta política contém ações destrutivas e de criação que não devem permanecer ativas indefinidamente:

```
ec2:CreateSecurityGroup / DeleteSecurityGroup
ec2:CreateLaunchTemplate / DeleteLaunchTemplate
ec2:RunInstances / TerminateInstances
ecs:CreateCluster / DeleteCluster / CreateService / DeleteService
ecs:CreateCapacityProvider / DeleteCapacityProvider
elasticloadbalancing:CreateLoadBalancer / DeleteLoadBalancer
rds:CreateDBInstance / DeleteDBInstance
autoscaling:CreateAutoScalingGroup / DeleteAutoScalingGroup
iam:CreateRole / DeleteRole / CreateInstanceProfile / DeleteInstanceProfile
ssm:PutParameter / DeleteParameter
logs:CreateLogGroup / DeleteLogGroup
route53:ChangeResourceRecordSets
```

**Quando remover:** após a execução do procedimento de limpeza da seção 7.

---

## 5. Dependências, restrições IAM e justificativas para `Resource: "*"`

### Dependências de criação (ordem obrigatória)

```
n8n-task-execution-role   ──→ necessária antes de: Task Definition
n8n-ec2-instance-role     ──→ necessária antes de: Instance Profile
n8n-ec2-instance-profile  ──→ necessária antes de: Launch Template
Launch Template           ──→ necessário antes de: Auto Scaling Group
Auto Scaling Group        ──→ necessário antes de: Capacity Provider ECS
Capacity Provider         ──→ necessário antes de: Cluster (associação)
```

### Restrição de `iam:PassRole`

`N8N-Lab-Deploy` concede `iam:PassRole` restrito a:
```
arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-*
arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/n8n-*
```

O usuário `n8n-lab` **não pode passar** para serviços AWS nenhuma role fora do prefixo `n8n-*`. Isso impede que o usuário conceda acesso à `ecsTaskExecutionRole` do BIA Cloud Lab ou a qualquer outra role da conta.

### Justificativas para `Resource: "*"`

| Statement | Ação(ões) | Motivo técnico |
|---|---|---|
| `EC2Write` | `ec2:Create*`, `ec2:Delete*`, `ec2:RunInstances` | A API do EC2 para operações de criação não aceita ARN de recurso antes da criação (ARN gerado pela AWS) |
| `ECSWrite` | `ecs:Create*`, `ecs:Delete*` | ARNs de cluster e service contêm identificadores gerados; não conhecidos antes da criação |
| `ALBWrite` | `elasticloadbalancing:Create*`, `Delete*` | ARNs do ALB, Target Group e Listener contêm hashes gerados na criação |
| `RDSReadForDeploy` | `rds:Describe*` | APIs de catálogo RDS (engine versions, orderable options, subnet groups) não aceitam ARN específico |
| `ASGWrite` | `autoscaling:*` | ARN do ASG inclui GUID gerado automaticamente; `DescribeAutoScalingGroups` não aceita ARN específico |
| `SSMPublicAMI` | `ssm:GetParameter` | Parâmetros públicos da AWS (`::parameter/aws/service/ecs/*`) estão em conta diferente (sem ID de conta no ARN) |
| `CloudWatchLogsDescribe` (01) | `logs:DescribeLogGroups` | Log group `/ecs/n8n-ec2` ainda não existe no momento da pré-validação |

### Restrições aplicadas onde tecnicamente suportado

| Statement | Resource restrito a |
|---|---|
| `RDSWrite` | `arn:aws:rds:us-east-2:<AWS_ACCOUNT_ID>:db:n8n` + recursos de suporte |
| `SSMWriteN8N` | ARNs exatos: `parameter/n8n/db_password` e `parameter/n8n/encryption_key` |
| `IAMRolesN8N` | Prefixo `n8n-*` em roles e instance profiles |
| `Route53WriteN8N` | Zona específica: `Z0200626TQFMAZ5GPD92` |
| `LogsWriteN8N` | Log group específico: `/ecs/n8n-ec2` |
| `IAMReadN8N` (01) | Prefixo `n8n-*` |
| `KMSDescribeSSM` (01) | ARN exato da chave `88a00481-a1aa-4f0d-b686-7777144770cf` |
| `CloudWatchLogsReadN8N` (01) | ARN exato do log group `/ecs/n8n-ec2` e seus streams |
| `SSMSecrets` (04 — exec role) | ARNs exatos dos dois parâmetros `/n8n/db_password` e `/n8n/encryption_key` |
| `CloudWatchLogs` (04 — exec role) | ARN exato do log group `/ecs/n8n-ec2:*` |

---

## 6. Proteção ao BIA Cloud Lab

Nenhum dos arquivos deste diretório concede acesso a recursos do BIA Cloud Lab. As restrições por prefixo e ARN específico garantem isolamento total:

| Recurso BIA | Protegido por |
|---|---|
| `ecsTaskExecutionRole` | `iam:PassRole` restrito a `n8n-*`; `iam:GetRole` restrito a `n8n-*` |
| `cluster-bia-app`, `service-bia-cloud-app` | Nenhuma ação de escrita ECS sem restrição de cluster (ECS não suporta ARN em Create*; mitigado pela nomenclatura `n8n-*`) |
| `bia-cloud-alb`, `bia-cloud` (RDS) | `RDSWrite` restrito a `db:n8n`; ALB não tem restrição por ARN antes da criação |
| `cloud-lab.bia.d2ns.com.br` | `route53:ChangeResourceRecordSets` restrito à zona `Z0200626TQFMAZ5GPD92` — a mesma zona, mas o CNAME `n8n.bia.d2ns.com.br` é um registro distinto |
| `/n8n/db_password`, `/n8n/encryption_key` | SSM Write restrito a estes dois ARNs exatos |

> **Atenção — Route 53:** a zona `bia.d2ns.com.br` é compartilhada com o BIA Cloud Lab. A permissão `route53:ChangeResourceRecordSets` na zona inteira permite ao usuário `n8n-lab` potencialmente modificar outros registros. Risco aceitável para laboratório; em produção, recomendaria criar uma subzona delegada exclusiva para o N8N.

---

## 7. Procedimento de limpeza IAM ao final do laboratório

Executar **após** a limpeza completa dos recursos AWS (seção 16 do plano):

```bash
PROFILE="--profile n8n-lab --region us-east-2"

# 1. Desanexar managed policies da instance role
aws iam detach-role-policy \
  --role-name n8n-ec2-instance-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role \
  $PROFILE

aws iam detach-role-policy \
  --role-name n8n-ec2-instance-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  $PROFILE

# 2. Remover role do instance profile e excluir
aws iam remove-role-from-instance-profile \
  --instance-profile-name n8n-ec2-instance-profile \
  --role-name n8n-ec2-instance-role $PROFILE

aws iam delete-instance-profile \
  --instance-profile-name n8n-ec2-instance-profile $PROFILE

# 3. Excluir instance role
aws iam delete-role --role-name n8n-ec2-instance-role $PROFILE

# 4. Excluir inline policy da execution role
aws iam delete-role-policy \
  --role-name n8n-task-execution-role \
  --policy-name n8n-execution-policy $PROFILE

# 5. Excluir execution role
aws iam delete-role --role-name n8n-task-execution-role $PROFILE

# 6. Obter ARNs das políticas gerenciadas criadas para o projeto
ACCT="<AWS_ACCOUNT_ID>"
ARN_DEPLOY="arn:aws:iam::${ACCT}:policy/N8N-Lab-Deploy"
ARN_PREVALIDATION="arn:aws:iam::${ACCT}:policy/N8N-Lab-PreValidation-ReadOnly"

# 7. Desanexar políticas do usuário n8n-lab
aws iam detach-user-policy \
  --user-name n8n-lab --policy-arn $ARN_DEPLOY $PROFILE

aws iam detach-user-policy \
  --user-name n8n-lab --policy-arn $ARN_PREVALIDATION $PROFILE

# 8. Excluir as políticas gerenciadas
aws iam delete-policy --policy-arn $ARN_DEPLOY
aws iam delete-policy --policy-arn $ARN_PREVALIDATION
```

> A política `N8N-Lab-Infrastructure-ReadOnly` não é removida — foi criada antes do Desafio 5 e pode ser mantida para uso futuro.

---

## 8. Referências rápidas

| Item | ARN / Valor |
|---|---|
| Usuário `n8n-lab` | `arn:aws:iam::<AWS_ACCOUNT_ID>:user/n8n-lab` |
| `n8n-task-execution-role` | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-task-execution-role` |
| `n8n-ec2-instance-role` | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-ec2-instance-role` |
| `n8n-ec2-instance-profile` | `arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/n8n-ec2-instance-profile` |
| KMS `aws/ssm` | `arn:aws:kms:us-east-2:<AWS_ACCOUNT_ID>:key/88a00481-a1aa-4f0d-b686-7777144770cf` |
| Hosted zone | `Z0200626TQFMAZ5GPD92` (bia.d2ns.com.br) |
| SSM db_password | `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/db_password` |
| SSM encryption_key | `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/encryption_key` |
| Log group | `arn:aws:logs:us-east-2:<AWS_ACCOUNT_ID>:log-group:/ecs/n8n-ec2` |
