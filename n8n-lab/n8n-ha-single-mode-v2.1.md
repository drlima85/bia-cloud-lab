# Desafio 5 — N8N na AWS: Single Mode com Auto-Recovery (Arquitetura do Instrutor)

**Projeto:** BIA Cloud Lab  
**Conta AWS:** <AWS_ACCOUNT_ID>  
**Região:** us-east-2  
**Versão do plano:** 2.1 (Revisado com Boas Práticas e Auto-Recovery)  
**Data:** 2026-11-09  
**Status:** Etapas 1 a 10 concluídas — Ambiente 100% Homologado e Operacional  

---

## 1. Objetivo e Escopo da Solução

### 1.1 Objetivo
Implantar a ferramenta de automação N8N na AWS com a arquitetura homologada pelo instrutor da Formação AWS: Amazon ECS com capacidade EC2 em modo `bridge` com Dynamic Port Mapping, exposto via Application Load Balancer com terminação HTTPS (porta 443), banco de dados dedicado Amazon RDS PostgreSQL e domínio próprio sob `n8n.bia.d2ns.com.br`.

### 1.2 Natureza da Arquitetura: Single-Mode com Auto-Recovery (Não HA)
Este ambiente de laboratório **não é uma solução de Alta Disponibilidade (HA) real / tolerante a falhas de Zona de Disponibilidade**, pois opera com:
- **1 única instância EC2** (`t3.micro`).
- **1 única Task ECS ativa** (`desiredCount=1`).
- **Amazon RDS PostgreSQL em Single-AZ**.

O que esta arquitetura oferece é **Recuperação Automática (Self-Healing)** contra falhas pontuais:
- **Crash do container N8N:** O ECS Service detecta a falha da task e inicia um novo container na mesma instância EC2 (~30–60 segundos).
- **Falha da instância EC2:** O Auto Scaling Group detecta o host não íntegro, encerra a máquina e provisiona uma nova instância (em us-east-2a ou us-east-2b), que se registra no cluster e recebe a task agendada pelo ECS (~3–5 minutos).
- **Indisponibilidade da AZ:** Ocorrerá interrupção temporária até que a infraestrutura da AZ afetada seja restabelecida ou redirecionada.

---

## 2. Decisões Arquiteturais Fundamentais

| Decisão | Escolha | Justificativa Técnica |
|---|---|---|
| **Runtime ECS** | EC2 (`t3.micro`) | Padrão do instrutor; menor custo em relação ao Fargate para operação contínua em laboratório. |
| **Network Mode** | `bridge` | O container utiliza a pilha de rede do host Docker (EC2). Garante tráfego de saída à internet via IP público da EC2 para execução de workflows e webhooks externos sem necessidade de NAT Gateway. |
| **Dynamic Port Mapping** | `hostPort: 0` e `containerPort: 5678` | O ECS Agent aloca portas efêmeras aleatórias (32768–65535) no host e as registra automaticamente no Target Group via ALB. |
| **Target Group** | Tipo `instance`, HTTP:5678 | Obrigatório para o modo de rede `bridge`. Configurado com `deregistration_delay` de 30 segundos para agilizar a drenagem de conexões em deploys e reinicializações. |
| **Health Check** | `/healthz` (HTTP 200) | Endpoint nativo de verificação de integridade do N8N na porta 5678. |
| **Capacidade ECS** | Capacity Provider (`cp-n8n-d2n`) | Vinculado ao Auto Scaling Group, com `managedScaling=DISABLED` para manter capacidade fixa e controlada de 1 máquina. |
| **ECS Service** | Strategy via Capacity Provider | Uso estrito de `--capacity-provider-strategy` (sem `--launch-type`), `minimumHealthyPercent=0`, `maximumPercent=100` e `availability-zone-rebalancing DISABLED`. |
| **Banco de Dados** | RDS PostgreSQL (`db.t3.micro`, 20 GB gp2) | Single-AZ, não público, retenção de backup 0, senha master recuperada com segurança via SSM Parameter Store. |
| **SSL do Banco** | `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` | Criptografia em trânsito (TLS) ativada sem dependência de montagem do pacote de certificados raiz CA da AWS dentro do container. |
| **Imagem N8N** | `n8nio/n8n:2.22.6` | Versão estável, homologada pelo instrutor e validada no Docker Hub para arquitetura x86_64. |
| **Memória da Task** | `memoryReservation: 650` MiB | Soft limit viável para o `t3.micro` (overhead do SO/Docker/ECS de ~300 MiB; ~700 MiB alocáveis para containers). |
| **DNS** | Registro A (Alias) no Route 53 | Apontamento nativo para o ALB na Hosted Zone existente `Z0200626TQFMAZ5GPD92`. |

---

## 3. Diagrama da Infraestrutura

```
                    Internet
                       │
                  HTTPS:443
                       │
          ┌────────────▼────────────┐
          │   ALB: n8n-d2n-alb      │  internet-facing
          │   SG:  n8n-alb          │  subnets: 2a + 2b
          │   ACM: *.bia.d2ns.com.br│
          └────────────┬────────────┘
                       │ HTTP (Porta Dinâmica 32768-65535)
          ┌────────────▼────────────┐
          │  Target Group           │
          │  tg-n8n-d2n             │  type=instance, port=5678
          │  healthcheck: /healthz  │  deregistration_delay: 30s
          └────────────┬────────────┘
                       │
          ┌────────────▼────────────┐
          │  ECS Service            │
          │  svc-n8n-d2n            │  desired=1, min=0%, max=100%
          │  Cluster: cluster-n8n-d2n
          └────────────┬────────────┘
                       │ bridge mode
          ┌────────────▼────────────┐
          │  EC2 Host (t3.micro)    │  SG: n8n-ec2 (inbound efêmero do ALB)
          │  Container: n8nio/n8n   │  port 5678 -> dynamic hostPort
          └────────────┬────────────┘
                       │ TCP:5432 (VPC privada)
          ┌────────────▼────────────┐
          │  RDS PostgreSQL         │
          │  n8n (db.t3.micro, gp2) │  private, no public access
          │  SG: n8n-db             │
          └─────────────────────────┘

  Route 53: n8n.bia.d2ns.com.br ──Alias A──► n8n-d2n-alb
```

---

## 4. Matriz de Recursos AWS e Nomenclaturas

| # | Recurso | Nome Identificador | Especificação / Regras |
|---|---|---|---|
| 1 | Security Group ALB | `n8n-alb` | Inbound TCP 443 de `0.0.0.0/0`. Outbound All. |
| 2 | Security Group EC2 | `n8n-ec2` | Inbound TCP 32768–65535 originado de `sg-n8n-alb`. Outbound All. |
| 3 | Security Group RDS | `n8n-db` | Inbound TCP 5432 originado de `sg-n8n-ec2`. Outbound All. |
| 4 | RDS PostgreSQL | `n8n` | db.t3.micro, 20 GB gp2, Single-AZ, sem IP público, retention 0. |
| 5 | Target Group | `tg-n8n-d2n` | target-type=instance, HTTP:5678, path /healthz, deregistration_delay=30s. |
| 6 | ALB | `n8n-d2n-alb` | Application Load Balancer, internet-facing, listener HTTPS 443. |
| 7 | ECS Cluster | `cluster-n8n-d2n` | Cluster ECS com capacidade EC2. |
| 8 | Launch Template | `lt-n8n-d2n` | t3.micro, AL2023 ECS AMI, user data registrando no cluster. |
| 9 | Auto Scaling Group | `asg-n8n-d2n` | min=1, max=1, desired=1, subnets 2a/2b. |
| 10 | Capacity Provider | `cp-n8n-d2n` | Vinculado a `asg-n8n-d2n`, managedScaling=DISABLED. |
| 11 | Log Group | `/ecs/n8n-ec2` | CloudWatch Logs com retenção padrão. |
| 12 | Task Definition | `task-def-n8n-d2n` | bridge mode, memoryReservation 650, imagem n8nio/n8n:2.22.6. |
| 13 | ECS Service | `svc-n8n-d2n` | Capacity Provider Strategy, desired=1, min=0%, max=100%. |
| 14 | Route 53 Record | `n8n.bia.d2ns.com.br` | Registro A (Alias) apontando para o ALB. |

---

## 5. Permissões IAM e Menor Privilégio

Todas as permissões do usuário `n8n-lab` utilizam **Políticas Gerenciadas pela AWS** (*AWS Managed Policies*). A política `IAMFullAccess` é tratada como exceção estritamente temporária de laboratório.

| Etapa | Operação | AWS Managed Policy | Alvo | Duração |
|---|---|---|---|---|
| **Etapa 1** | SSM Parameter Store | `AmazonSSMFullAccess` | Usuário `n8n-lab` | Mantida para consultas e deploys. |
| **Etapa 2** | Security Groups | `AmazonEC2FullAccess` | Usuário `n8n-lab` | Mantida (usada no Launch Template). |
| **Etapa 3** | RDS PostgreSQL | `AmazonRDSFullAccess` | Usuário `n8n-lab` | Revogável após criação do banco. |
| **Etapa 4** | Consulta ACM | `AWSCertificateManagerReadOnlyAccess` | Usuário `n8n-lab` | Temporária (leitura). |
| **Etapa 5** | ALB e Target Group | `ElasticLoadBalancingFullAccess` | Usuário `n8n-lab` | Mantida durante a implantação. |
| **Etapa 6** | IAM Roles (EC2 e Task) | **`IAMFullAccess` (EXCEPCIONAL)** | Usuário `n8n-lab` | **REMOVIDA IMEDIATAMENTE APÓS A ETAPA 6.** |
| **Etapa 6** | Cluster e ASG | `AmazonECS_FullAccess`<br>`AutoScalingFullAccess` | Usuário `n8n-lab` | Mantidas para gerenciamento do cluster. |
| **Etapa 7** | CloudWatch Logs | `CloudWatchLogsFullAccess` | Usuário `n8n-lab` | Mantida para observabilidade. |
| **Etapa 8/9** | Task Def e Service | `AmazonECS_FullAccess` | Usuário `n8n-lab` | Já atribuída na Etapa 6. |
| **Etapa 10** | Route 53 DNS | `AmazonRoute53FullAccess` | Usuário `n8n-lab` | Revogável após criar o Alias. |

### 5.1 Roles Internas do Serviço
- **`n8n-ec2-instance-role`:**
  - Anexadas: `AmazonEC2ContainerServiceforEC2Role` e `AmazonSSMManagedInstanceCore`.
- **`n8n-task-execution-role`:**
  - Anexada: `service-role/AmazonECSTaskExecutionRolePolicy`.
  - Inline Policy `n8n-ssm-secrets-policy`: Permite `ssm:GetParameters` nos recursos `arn:aws:ssm:us-east-2:<AWS_ACCOUNT_ID>:parameter/n8n/*`.

---

## 6. Sequência de Execução Detalhada (10 Etapas)

### Etapa 1 — Preparação Local (CONCLUÍDA)
- Validado: `n8n-lab/.env`, `n8n-lab/.env.example`.
- Validado: SSM SecureString `/n8n/db_password` e `/n8n/encryption_key` ativos.

### Etapa 2 — Security Groups (CONCLUÍDA)
- Criar `n8n-alb` (porta 443 aberta para 0.0.0.0/0) — `sg-0c730a80bd90e04b6`.
- Criar `n8n-ec2` (portas 32768–65535 permitidas a partir de `n8n-alb`) — `sg-0f19e61de96d6e92b`.
- Criar `n8n-db` (porta 5432 permitida a partir de `n8n-ec2`) — `sg-031c278d1201dbd7f`.

### Etapa 3 — RDS PostgreSQL (CONCLUÍDA)
- Criar instância `n8n` (`db.t3.micro`, 20 GB gp2, Single-AZ, não pública).
- Aguardar status `available` e registrar o endpoint DNS do banco (`n8n.ctekugasc68m.us-east-2.rds.amazonaws.com`).

### Etapa 4 — Validação do ACM (CONCLUÍDA)
- Consultar certificado wildcard `*.bia.d2ns.com.br` existente em us-east-2 e validar status `ISSUED` — ARN: `arn:aws:acm:us-east-2:<AWS_ACCOUNT_ID>:certificate/56a03714-9967-4655-b162-d4badfd3445a`.

### Etapa 5 — ALB e Target Group (CONCLUÍDA)
- Criar Target Group `tg-n8n-d2n` (tipo `instance`, porta 5678, path `/healthz`, deregistration_delay: 30s) — `arn:aws:elasticloadbalancing:us-east-2:<AWS_ACCOUNT_ID>:targetgroup/tg-n8n-d2n/f7b75aaea2ff2e84` (atributo `deregistration_delay.timeout_seconds=30` validado e ativo).
- Criar ALB `n8n-d2n-alb` internet-facing nas subnets 2a e 2b com SG `n8n-alb` — `n8n-d2n-alb-56749819.us-east-2.elb.amazonaws.com`.
- Criar Listener HTTPS 443 associando o certificado ACM e forward para `tg-n8n-d2n` — `arn:aws:elasticloadbalancing:us-east-2:<AWS_ACCOUNT_ID>:listener/app/n8n-d2n-alb/1b169b275ab952f6/b70a6841b861e714`.

### Etapa 6 — ECS Cluster, Roles e Capacidade EC2 (CONCLUÍDA)
- Roles `n8n-ec2-instance-role` e `n8n-task-execution-role` e instance profile `n8n-ec2-instance-profile` criados com menor privilégio.
- Cluster `cluster-n8n-d2n` criado e ativo.
- Launch Template `lt-n8n-d2n` (`lt-0a06127c05665549b`) configurado com AL2023 ECS AMI (`ami-030831d5502ebf96d`), `t3.micro`, SG `n8n-ec2` e auto-registro no cluster via User Data.
- Auto Scaling Group `asg-n8n-d2n` (min=1, max=1, desired=1) provisionado nas subnets 2a e 2b.
- Capacity Provider `cp-n8n-d2n` (managed scaling DISABLED) criado e vinculado ao cluster com default strategy.
- Container Instance `i-0aa9ffe16a7b2aa26` registrada como `ACTIVE` no cluster com **916 MiB de memória disponível** para a task.

### Etapa 7 — CloudWatch Logs (CONCLUÍDA)
- Criar Log Group `/ecs/n8n-ec2` — `arn:aws:logs:us-east-2:<AWS_ACCOUNT_ID>:log-group:/ecs/n8n-ec2:*` (retenção padrão).

### Etapa 8 — Task Definition (CONCLUÍDA)
- Registrar `task-def-n8n-d2n` no modo `bridge`, imagem `n8nio/n8n:2.22.6`, `memoryReservation: 650`, Dynamic Port Mapping (`hostPort: 0`, `containerPort: 5678`), variáveis de ambiente (incluindo `DB_POSTGRESDB_SSL_ENABLED=true` e `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false`) e segredos SSM — ARN ativo: `arn:aws:ecs:us-east-2:<AWS_ACCOUNT_ID>:task-definition/task-def-n8n-d2n:2`.

### Etapa 9 — ECS Service (CONCLUÍDA)
- Criar `svc-n8n-d2n` utilizando Capacity Provider Strategy (`cp-n8n-d2n`, weight=1), desired=1, min=0%, max=100%, rebalancing DISABLED, vinculado ao Target Group `tg-n8n-d2n`.
- Target `i-0aa9ffe16a7b2aa26:32768` registrado dinamicamente e validado em estado `healthy`.
- Task `57efd60c4c33485da8f9eeb389d64e14` em `RUNNING`, steady state atingido e migrações do PostgreSQL concluídas com sucesso.

### Etapa 10 — Route 53 e Validação Final (CONCLUÍDA)
- Criar registro A (Alias) para `n8n.bia.d2ns.com.br` apontando para o DNS name do ALB na Hosted Zone `Z0200626TQFMAZ5GPD92` (Alias Hosted Zone ID `Z3AADJGX6KTTL2`, `EvaluateTargetHealth=false`).
- Sincronização `INSYNC` confirmada, resolução DNS pública validada, acesso HTTPS testado fim a fim (HTTP/2 200) com certificado wildcard `*.bia.d2ns.com.br` válido e endpoint `/healthz` operacional (`{"status":"ok"}`).

---

## 7. Roteiro de Testes e Validação Final

1. **DNS e Certificado:** Resolução de `n8n.bia.d2ns.com.br` e validação do handshake TLS 1.3.
2. **Target Group Health:** Target em estado `healthy` após registro dinâmico de porta.
3. **Conexão com Banco:** Logs do N8N confirmando migrações executadas com sucesso no PostgreSQL.
4. **Aplicação:** Acesso a `https://n8n.bia.d2ns.com.br` com exibição da tela de onboarding/login.

---

## 8. Procedimento de Limpeza dos Recursos

Ao término do desafio, a desmontagem ocorre na ordem estrita para evitar bloqueios de dependência:
1. ECS Service (desired=0 e delete)
2. Task Definition (deregister)
3. ASG (zerar e delete)
4. Capacity Provider e Launch Template (delete)
5. ECS Cluster (delete)
6. ALB e Target Group (delete)
7. RDS PostgreSQL (delete com skip final snapshot)
8. Registro Route 53 (delete record)
9. Security Groups (`n8n-db`, `n8n-ec2`, `n8n-alb`)
10. Log Group CloudWatch
11. IAM Roles e Instance Profile
