# Guia Operacional IAM — Desafio 5: N8N na AWS

**Projeto:** BIA Cloud Lab AWS  
**Módulo:** Desafio 5 — N8N em Produção  
**Região:** `us-east-2` (Ohio)  
**Conta:** `<AWS_ACCOUNT_ID>`  
**Referência Arquitetural:** [`n8n-ha-single-mode-v2.1.md`](../n8n-ha-single-mode-v2.1.md)  
**Documento de Governança e Segurança IAM:** [`acesso.md`](acesso.md)  

---

## 1. Visão Geral do Guia Operacional

Este documento é o guia prático de execução para provisionamento, configuração e limpeza das identidades, perfis e permissões do **Desafio 5**. Para a fundamentação teórica de menor privilégio e análise de governança, consulte o documento [`acesso.md`](acesso.md).

> [!IMPORTANT]
> **Arquivos Operacionais Locais:**  
> Os modelos JSON citados neste roteiro (`01` a `07`) residem exclusivamente no diretório local `n8n-lab/iam/`. Eles são utilizados para a configuração no console ou via AWS CLI durante a implantação e **permanecem apenas no ambiente local**, sendo ignorados pelo Git para manter o repositório GitHub limpo e seguro.

---

## 2. Catálogo de Artefatos Operacionais Locais (`n8n-lab/iam/`)

A tabela abaixo descreve os artefatos locais gerados para a operação IAM:

| Arquivo Local | Tipo de Artefato | Entidade Vinculada | Finalidade Operacional |
|---|---|---|---|
| `01-policy-prevalidation-readonly.json` | Managed Policy | Usuário `n8n-lab` | Permissões de leitura para pré-validação de dependências. |
| `02-policy-deploy.json` | Managed Policy | Usuário `n8n-lab` | Permissões temporárias de escrita para deploy e limpeza. |
| `03-trust-policy-ecs-tasks.json` | Trust Policy | Role `n8n-task-execution-role` | Permite que `ecs-tasks.amazonaws.com` assuma a role da task. |
| `04-inline-policy-execution-role.json` | Inline Policy | Role `n8n-task-execution-role` | Acesso estrito a segredos SSM e entrega de logs CloudWatch. |
| `05-trust-policy-ec2.json` | Trust Policy | Role `n8n-ec2-instance-role` | Permite que `ec2.amazonaws.com` assuma a role do host EC2. |
| `06-instance-role-managed-policies.json` | Referência | Role `n8n-ec2-instance-role` | Lista de ARNs das políticas AWS gerenciadas necessárias. |
| `07-instance-profile.json` | Referência | Profile `n8n-ec2-instance-profile` | Comandos para criação e associação do instance profile. |

---

## 3. Ordem Obrigatória de Provisionamento e Dependências

Para evitar erros de dependência durante o provisionamento da infraestrutura ECS e EC2, as identidades IAM devem ser criadas na ordem exata indicada abaixo:

```
n8n-task-execution-role   ──→ Requisito para: Registro da Task Definition
n8n-ec2-instance-role     ──→ Requisito para: Criação do Instance Profile
n8n-ec2-instance-profile  ──→ Requisito para: Criação do Launch Template
Launch Template           ──→ Requisito para: Criação do Auto Scaling Group
Auto Scaling Group        ──→ Requisito para: Criação do Capacity Provider ECS
Capacity Provider         ──→ Requisito para: Associação ao ECS Cluster
```

---

## 4. Passo a Passo de Execução

### Fase A — Pré-implantação (Pré-validação)
1. **Política de Pré-Validação:**
   * Criar a política gerenciada `N8N-Lab-PreValidation-ReadOnly` utilizando o JSON operacional local `01-policy-prevalidation-readonly.json`.
   * Anexar a política ao usuário IAM `n8n-lab`.

### Fase B — Implantação da Infraestrutura
1. **Política de Deploy (Temporária):**
   * Criar a política gerenciada `N8N-Lab-Deploy` com o conteúdo de `02-policy-deploy.json` e anexá-la ao usuário `n8n-lab`.
2. **Criação da `n8n-task-execution-role`:**
   * Criar a role com a trust policy `03-trust-policy-ecs-tasks.json`.
   * Adicionar a inline policy `n8n-execution-policy` utilizando `04-inline-policy-execution-role.json`.
3. **Criação da `n8n-ec2-instance-role`:**
   * Criar a role com a trust policy `05-trust-policy-ec2.json`.
   * Anexar as duas políticas gerenciadas da AWS:
     * `arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role`
     * `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`
4. **Criação do Instance Profile:**
   * Criar o instance profile `n8n-ec2-instance-profile` e associar a role `n8n-ec2-instance-role` (conforme `07-instance-profile.json`).

---

## 5. Procedimento de Limpeza IAM ao Término do Laboratório

A desmontagem das identidades IAM deve ser executada **após a exclusão completa dos recursos computacionais da AWS** (ECS Service, ASG, Launch Template, ALB e RDS).

Executar os comandos abaixo com o perfil `n8n-lab` na região `us-east-2`:

```bash
PROFILE="--profile n8n-lab --region us-east-2"
ACCT="<AWS_ACCOUNT_ID>"

# 1. Desanexar políticas gerenciadas da role da instância EC2
aws iam detach-role-policy \
  --role-name n8n-ec2-instance-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role \
  $PROFILE

aws iam detach-role-policy \
  --role-name n8n-ec2-instance-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  $PROFILE

# 2. Remover role do instance profile e excluir profile
aws iam remove-role-from-instance-profile \
  --instance-profile-name n8n-ec2-instance-profile \
  --role-name n8n-ec2-instance-role \
  $PROFILE

aws iam delete-instance-profile \
  --instance-profile-name n8n-ec2-instance-profile \
  $PROFILE

# 3. Excluir instance role
aws iam delete-role --role-name n8n-ec2-instance-role $PROFILE

# 4. Excluir inline policy da execution role
aws iam delete-role-policy \
  --role-name n8n-task-execution-role \
  --policy-name n8n-execution-policy \
  $PROFILE

# 5. Excluir execution role
aws iam delete-role --role-name n8n-task-execution-role $PROFILE

# 6. Desanexar e excluir as políticas gerenciadas do usuário n8n-lab
ARN_DEPLOY="arn:aws:iam::${ACCT}:policy/N8N-Lab-Deploy"
ARN_PREVALIDATION="arn:aws:iam::${ACCT}:policy/N8N-Lab-PreValidation-ReadOnly"

aws iam detach-user-policy --user-name n8n-lab --policy-arn $ARN_DEPLOY $PROFILE
aws iam detach-user-policy --user-name n8n-lab --policy-arn $ARN_PREVALIDATION $PROFILE

aws iam delete-policy --policy-arn $ARN_DEPLOY
aws iam delete-policy --policy-arn $ARN_PREVALIDATION
```

---

## 6. Tabela de Referências Rápidas

| Recurso | Tipo | ARN / Identificador |
|---|---|---|
| Usuário de Automação | IAM User | `arn:aws:iam::<AWS_ACCOUNT_ID>:user/n8n-lab` |
| Task Execution Role | IAM Role | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-task-execution-role` |
| EC2 Instance Role | IAM Role | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-ec2-instance-role` |
| Instance Profile | Instance Profile | `arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/n8n-ec2-instance-profile` |
| Parâmetro DB Password | SSM Parameter | `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/db_password` |
| Parâmetro Encryption Key | SSM Parameter | `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/encryption_key` |
| Log Group ECS | CloudWatch Logs | `arn:aws:logs:us-east-2:<AWS_ACCOUNT_ID>:log-group:/ecs/n8n-ec2` |
