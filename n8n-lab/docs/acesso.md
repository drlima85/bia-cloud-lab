# Governança e Segurança IAM — Desafio 5: N8N na AWS

**Projeto:** BIA Cloud Lab AWS  
**Módulo:** Desafio 5 — N8N em Produção  
**Região:** `us-east-2` (Ohio)  
**Conta:** `<AWS_ACCOUNT_ID>`  
**Referência Arquitetural:** [`n8n-ha-single-mode-v2.1.md`](../n8n-ha-single-mode-v2.1.md)  
**Guia Operacional Passo a Passo:** [`README-acesso.md`](README-acesso.md)  

---

## 1. Visão Geral de Governança e Escopo de Acesso

A modelagem de identidades e acessos (IAM) do Desafio 5 foi estruturada com foco em **menor privilégio**, **segregação de responsabilidades** e **proteção aos recursos preexistentes da aplicação BIA Cloud Lab**.

> [!NOTE]
> **Artefatos Operacionais Locais:**  
> Os arquivos JSON com as definições de políticas e trust policies referenciados neste documento residem exclusivamente no diretório local `n8n-lab/iam/` para provisionamento do ambiente e **não são versionados no repositório público do GitHub**, garantindo que definições operacionais detalhadas não componham a superfície pública do projeto. Para os comandos de criação e limpeza, consulte o [`README-acesso.md`](README-acesso.md).

---

## 2. Arquitetura de Identidades e Roles

A solução implementa três identidades principais, cada uma com escopo restrito às suas funções no ciclo de vida da infraestrutura:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Identidades do Desafio 5                        │
├──────────────────────────┬─────────────────────────┬───────────────────┤
│    Usuário n8n-lab       │   Execution Role (Task) │   Instance Role   │
│                          │                         │                   │
│ • Deploy transitório     │ • ecs-tasks.amazonaws   │ • ec2.amazonaws   │
│ • Pré-validação RO       │ • Leitura SSM (/n8n/*)  │ • ECS Agent EC2   │
│ • Desanexado pós-deploy  │ • CloudWatch Logs       │ • SSM Session Mgr │
└──────────────────────────┴─────────────────────────┴───────────────────┘
```

### 2.1 Role de Execução do Container (`n8n-task-execution-role`)
* **Entidade Confiável (Trust Policy):** `ecs-tasks.amazonaws.com`.
* **Propósito:** Utilizada estritamente pelo ECS Agent no plano de controle do host EC2 durante o ciclo de bootstrapping da Task.
* **Escopo de Acesso (Inline Policy `n8n-execution-policy`):**
  * `ssm:GetParameters` nos parâmetros restritos:
    * `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/db_password`
    * `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/encryption_key`
  * Criação de log stream e entrega de eventos de log no Log Group `arn:aws:logs:us-east-2:<AWS_ACCOUNT_ID>:log-group:/ecs/n8n-ec2:*`.
* **Princípio de Menor Privilégio em Runtime:** O container N8N em execução opera em modo `bridge` e **não recebe uma Task Role**. Ele não possui credenciais AWS injetadas em runtime, impedindo que fluxos de trabalho ou automações executem chamadas à AWS API sem credenciais explicitamente configuradas no editor de nós do N8N.

### 2.2 Role da Instância EC2 (`n8n-ec2-instance-role`) & Instance Profile
* **Entidade Confiável (Trust Policy):** `ec2.amazonaws.com`.
* **Instance Profile:** `n8n-ec2-instance-profile`.
* **Políticas Gerenciadas AWS Anexadas:**
  1. `AmazonEC2ContainerServiceforEC2Role`: Concede permissões essenciais para que o daemon do ECS Agent registre a instância EC2 no cluster `cluster-n8n-d2n` e coordene o ciclo de vida dos containers.
  2. `AmazonSSMManagedInstanceCore`: Permite o gerenciamento e acesso seguro à instância através do **AWS Systems Manager Session Manager**, eliminando a necessidade de abrir portas SSH (TCP 22) ou associar Key Pairs às máquinas.

### 2.3 Usuário de Automação e Deploy (`n8n-lab`)
* **Políticas Gerenciadas Associadas:**
  * `N8N-Lab-Infrastructure-ReadOnly`: Auditoria contínua de infraestrutura (mantida).
  * `N8N-Lab-PreValidation-ReadOnly`: Verificações prévias de dependências (AMIs, VPC, Subnets).
  * `N8N-Lab-Deploy`: Política de provisionamento e limpeza com ações de escrita. Conforme as diretrizes de governança, **esta política possui caráter estritamente temporário e deve ser desanexada imediatamente após a conclusão do ciclo de vida do ambiente**.

---

## 3. Análise Crítica e Justificativas para `Resource: "*"`

O modelo de menor privilégio impõe que recursos específicos sejam delimitados por ARN sempre que tecnicamente possível. Onde a AWS API não suporta especificação granular no momento da emissão da chamada, o uso do curinga `*` foi documentado e justificado:

| Ação IAM | Motivo Técnico da Inviabilidade de ARN Específico | Mitigação Implementada |
|---|---|---|
| `ec2:RunInstances`, `ec2:CreateSecurityGroup` | As operações de criação do EC2 não aceitam ARN de recursos que ainda não foram gerados no momento da chamada. | Escopo de deploy restrito à região `us-east-2` e tags de governança obrigatórias. |
| `ecs:CreateCluster`, `ecs:CreateService` | A API do ECS não filtra operações `Create` por ARN específico de cluster na versão utilizada. | Nomenclatura padronizada sob o namespace `n8n-*`. |
| `elasticloadbalancing:Create*` | ARNs do ALB, Target Group e Listener contêm identificadores e hashes gerados em tempo de execução. | Permissões de escrita contidas na política temporária de deploy. |
| `autoscaling:CreateAutoScalingGroup` | O identificador do ASG inclui sufixos gerados dinamicamente. | Configuração restrita ao Launch Template `lt-n8n-d2n`. |
| `rds:Describe*` de Catálogo | APIs de consulta a versões de engine (`DescribeDBEngineVersions`) e tipos de instância são serviços de catálogo globais. | Operações estritamente de leitura (Read-Only). |

### Restrições Granulares Efetivamente Aplicadas:
* **Escrita RDS:** Restrita a instâncias no banco `db:n8n`.
* **Segredos SSM:** Restrita aos caminhos exatos `/n8n/db_password` e `/n8n/encryption_key`.
* **PassRole:** Restrita explicitamente a roles com prefixo `n8n-*`.
* **CloudWatch Logs:** Restrita ao Log Group `/ecs/n8n-ec2*`.

---

## 4. Proteção e Coexistência com o Projeto BIA Cloud Lab

O ambiente do Desafio 5 foi projetado para coexistir na mesma conta AWS da aplicação principal BIA Cloud Lab sem causar impactos acidentais. A governança foi estabelecida sobre os seguintes controles técnicos reais:

1. **Blindagem de PassRole:**
   A política de deploy restringe a ação `iam:PassRole` a:
   ```text
   arn:aws:iam::<AWS_ACCOUNT_ID>:role/n8n-*
   arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/n8n-*
   ```
   Isso garante que o usuário `n8n-lab` não consiga delegar roles com privilégios de outros projetos (como a `ecsTaskExecutionRole` do BIA) para serviços ou instâncias.
2. **Segregação de Segurança em Rede:**
   Security Groups dedicados (`n8n-alb`, `n8n-ec2`, `n8n-db`) isolados dos Security Groups da BIA, sem regras de compartilhamento de tráfego entre os dois ecossistemas.
3. **Ponto de Atenção — Route 53 Compartilhado:**
   A zona DNS `bia.d2ns.com.br` (`Z0200626TQFMAZ5GPD92`) é compartilhada. A política concedeu `route53:ChangeResourceRecordSets` na hosted zone. A proteção dos registros preexistentes do BIA foi assegurada por **isolamento de apontamento** (criação exclusiva do subdomínio `n8n.bia.d2ns.com.br`). Em ambientes corporativos de produção, a recomendação é a criação de uma subzona delegada exclusiva para automações.

---

## 5. Referências de Identidades

| Identificador | Tipo | Finalidade Principal |
|---|---|---|
| `n8n-task-execution-role` | IAM Role | Leitura de segredos SSM e entrega de logs no ECS. |
| `n8n-ec2-instance-role` | IAM Role | Comunicação do ECS Agent e túnel via SSM Session Manager. |
| `n8n-ec2-instance-profile` | Instance Profile | Associação da role EC2 ao Launch Template `lt-n8n-d2n`. |
| `N8N-Lab-Deploy` | Managed Policy | Política transitória de provisionamento (revogada pós-laboratório). |
| `N8N-Lab-PreValidation-ReadOnly` | Managed Policy | Validação de pré-requisitos antes do deploy. |
