# Desafio 6 — N8N Queue Mode na AWS com Amazon ElastiCache Valkey

**Projeto:** BIA Cloud Lab AWS  
**Módulo:** Desafio 6 — Orquestração Escalável de N8N em Fila Distribuída  
**Região AWS:** `us-east-2` (Ohio)  
**Versão do N8N:** `n8nio/n8n:2.22.6` (Docker Hub, x86_64)  
**Status:** Implantação concluída, validada e homologada com testes de resiliência  

---

## 1. Visão Geral da Solução e Evolução Arquitetural

O **Desafio 6** representa a evolução arquitetural da plataforma de automação **N8N** na AWS, transitando do modelo monólito (*Single-Mode* — Desafio 5) para o modelo desacoplado distribuído em fila (**Queue Mode**), em total conformidade com a arquitetura de referência homologada para a Formação AWS.

### Comparativo Arquitetural: Desafio 5 vs. Desafio 6

| Dimensão Técnica | Desafio 5 (Single-Mode) | Desafio 6 (Queue Mode) |
|---|---|---|
| **Padrão Arquitetural** | Monólito em container único (UI + Execuções) | Desacoplado: 1 Main (UI/Webhooks) + 2 Workers em fila |
| **Message Broker** | Inexistente (execuções locais em memória) | **Amazon ElastiCache Valkey 7.2** com TLS e AUTH Token |
| **Capacidade Computacional** | 1 instância EC2 `t3.micro` (1 GB RAM) | 1 instância EC2 `t3.small` (2 GB RAM) via ECS Capacity Provider |
| **Impacto de Sobrecarga** | Webhooks e interface travam sob carga pesada | Webhooks respondem instantaneamente; fila absorve picos |
| **Resiliência a Falhas** | Reinício do container interrompe recepção | Workers podem reiniciar/escalar sem derrubar o Main ou perder jobs |

---

## 2. Arquitetura e Decisões Técnicas

```
                                  Internet
                                     │
                                 HTTPS:443
                                     │
                     ┌───────────────▼───────────────┐
                     │    Route 53 (Alias A)         │ n8n.bia.d2ns.com.br
                     │    ACM Wildcard RSA-2048      │ *.bia.d2ns.com.br
                     └───────────────┬───────────────┘
                                     │
                     ┌───────────────▼───────────────┐
                     │ Application Load Balancer     │ n8n-d2n-alb
                     │ (HTTPS:443 · HTTP/2)          │ SG: n8n-alb (TCP 443)
                     └───────────────┬───────────────┘
                                     │ Dynamic Port Mapping
                                     │ (TCP efêmera, ex: 32769)
                                     ▼
┌────────────────────────────────────┼────────────────────────────────────┐
│ Amazon EC2 Host (t3.small · AL2023 ECS Optimized · SG: n8n-ec2)        │
│                                                                        │
│   ┌────────────────────────────────▼────────────────────────────────┐  │
│   │ ECS Service Main (svc-n8n-main · desiredCount: 1)               │  │
│   │ Task: UI + Webhooks + Scheduler (Porta 5678 -> Porta Dinâmica do Host)  │  │
│   │ Soft Limit: 650 MiB · Hard Limit: 800 MiB · (ex. observada no teste: 32769) │
│   └───────────────┬─────────────────────────────────┬───────────────┘  │
│                   │                                 │                  │
│                   │ Enfileira Job (TLS:6379)        │ Schemas (5432)   │
│                   ▼                                 ▼                  │
│   ┌────────────────────────────────┐ ┌──────────────────────────────┐  │
│   │ ECS Service Worker             │ │ Amazon RDS PostgreSQL 16.13  │  │
│   │ (svc-n8n-worker · desired: 2)  │ │ (db.t3.micro · Privado VPC)  │  │
│   │ Tasks: w1 e w2                 │ │ SG: n8n-db (TCP 5432)        │  │
│   │ Soft: 450 MiB · Hard: 550 MiB  │ └──────────────▲───────────────┘  │
│   │ Concurrency: 5 por task        │                │                  │
│   └───────────────┬────────────────┘                │                  │
│                   │                                 │                  │
│                   │ Drena Fila (TLS:6379 com AUTH)  │ Grava Execuções  │
│                   ▼                                 │                  │
│   ┌─────────────────────────────────────────────────┴───────────────┐  │
│   │ Amazon ElastiCache Valkey 7.2 (cache.t4g.micro · Replication Grp)│  │
│   │ Endpoint: master.n8n-valkey...:6379 · SG: n8n-valkey-sg         │  │
│   │ 🔒 TLS Obrigatório + 🔑 AUTH Token via SSM Parameter Store     │  │
│   └─────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

> [!TIP]
> Para uma visualização detalhada e navegável, consulte o [Diagrama Mermaid Completo](DIAGRAMA-ARQUITETURA.md) e a versão visual gráfica vetorial interativa em [`n8n-queue-mode-architecture.html`](n8n-queue-mode-architecture.html).

### Matriz de Decisões Técnicas

| Componente | Decisão Técnica | Justificativa |
|---|---|---|
| **Orquestrador** | Amazon ECS com capacidade EC2 | Menor custo operacional para laboratório contínuo se comparado ao AWS Fargate. |
| **Instância Host** | 1x `t3.small` (2 vCPU, 2 GB RAM) | Entrega 1.913 MiB de memória registrada no ECS, suficiente para acomodar 1 Main (650 MiB) e 2 Workers (2x 450 MiB), mantendo folga de 363 MiB de capacidade residual de agendamento do ECS (não confundir com RAM física livre do sistema operacional). |
| **Modo de Rede** | `bridge` com Dynamic Port Mapping | Permite comunicação direta à internet pelo IP público do host sem necessidade de NAT Gateway (economia crítica de ~$32/mês). O hostPort 0 atribui portas efêmeras dinâmicas gerenciadas pelo ECS (ex. 32769 observada durante o teste). |
| **Message Broker** | Amazon ElastiCache Valkey 7.2 (`cache.t4g.micro`) | Engine open-source de alta performance. Provisionado via Replication Group de nó único para viabilizar criptografia em trânsito (TLS) e autenticação obrigatória (AUTH Token). |
| **Banco de Dados** | Amazon RDS PostgreSQL 16.13 (`db.t3.micro`) | Banco relacional totalmente privado na VPC para persistência de workflows, credenciais, histórico e execuções. |
| **Target Group** | Tipo `instance`, Dynamic Port Mapping | Roteia exclusivamente para a porta dinâmica do host vinculada ao container Main (porta 5678). Workers operam sem associação ao Target Group. |
| **Health Check** | Path `/healthz` (delay 30s) | Endpoint nativo da API do N8N avaliado na porta mapeada pelo ALB. |
| **Injeção de Segredos** | AWS Systems Manager Parameter Store (`SecureString`) | Senhas do banco, chave de encriptação do n8n e token AUTH do Valkey são injetados em runtime pelo ECS Agent via IAM Role, sem exposição em arquivos ou texto puro. |

---

## 3. Recursos Provisionados e Validados na AWS

Todos os recursos foram implantados com sucesso na região `us-east-2` (Ohio):

| Recurso AWS | Identificador / Nome | Especificação Técnica | Status |
|---|---|---|---|
| **Route 53** | `n8n.bia.d2ns.com.br` | Registro Alias A apontando para o ALB | **`INSYNC`** / Ativo |
| **Certificado ACM** | `*.bia.d2ns.com.br` | Wildcard RSA-2048 (Recurso Compartilhado) | **`ISSUED`** / Válido |
| **Application Load Balancer** | `n8n-d2n-alb` | Internet-facing, subnets públicas `2a` e `2b`, HTTPS:443 | **`active`** |
| **Target Group** | `tg-n8n-d2n` | Tipo `instance`, porta dinâmica do host (ex. `32769` observada no teste), path `/healthz` | **`healthy`** |
| **Auto Scaling Group** | `asg-n8n-d2n` | `min=1`, `max=1`, `desired=1` (AMI AL2023 ECS-Optimized) | **`InService`** |
| **Host EC2 ECS** | Instância `t3.small` (`i-09f7979988ba3b9b7`) | 2 vCPU, 2 GB RAM (1.913 MiB registradas, 363 MiB de capacidade residual de agendamento) | **`ACTIVE`** |
| **ECS Cluster** | `cluster-n8n-d2n` | Capacity Provider `cp-n8n-d2n` associado como default | **`ACTIVE`** |
| **ECS Service Main** | `svc-n8n-main` | `task-def-n8n-main:1` (1 task ativa com porta dinâmica do host, ex. `32769` no teste) | **`RUNNING`** |
| **ECS Service Worker** | `svc-n8n-worker` | `task-def-n8n-worker:1` (2 tasks ativas sem ALB) | **`RUNNING`** |
| **ElastiCache Valkey** | `n8n-valkey` | Replication Group nó único (`cache.t4g.micro`), TLS + AUTH | **`available`** |
| **RDS PostgreSQL** | `n8n` | `db.t3.micro`, 20 GB gp2, PostgreSQL 16.13, privado na VPC | **`available`** |
| **CloudWatch Logs** | `/ecs/n8n-ec2` | Retenção 7 dias; streams `n8n-main` e `n8n-worker` | **Ativo** |
| **SSM Parameters** | `/n8n/db_password`, `/n8n/encryption_key`, `/n8n/valkey_token` | `SecureString` criptografados via KMS padrão | **Ativo** |

---

## 4. Homologação do Teste de Resiliência da Fila (Queue Mode)

O teste homologou o desacoplamento real entre a recepção das requisições e seu processamento assíncrono através de um workflow de teste com gatilho Webhook configurado em modo `Immediately` (`responseMode: "onReceived"`).

### 4.1 Sequência do Teste Prático

1. **Execução de Controle (Workers Ativos):** Chamada inicial ao webhook processada imediatamente com sucesso (Execution ID 1 concluído em 2.128s).
2. **Parada Total dos Workers:** Serviço `svc-n8n-worker` reduzido para `desiredCount=0`. Comprovou-se via CLI que `runningCount == 0`.
3. **Disparo das Requisições:** Três chamadas POST consecutivas enviadas ao endpoint público (`teste-01`, `teste-02`, `teste-03`). Todas receberam **`HTTP/2 200 OK`** instantaneamente pelo Main via ALB.
4. **Auditoria Pré-Retomada:**
   - **PostgreSQL (`execution_entity`):** IDs 2, 3 e 4 criados com status **`new`** e campos `startedAt: null` e `stoppedAt: null`.
   - **ElastiCache Valkey:** Fila `bull:jobs:wait` registrou exatamente `waitingJobsCount: 3` (`["4", "3", "2"]`).
5. **Retomada dos Workers:** Serviço restaurado para `desiredCount=2`. As tarefas iniciaram, conectaram ao Valkey e drenaram a fila pendente.

### 4.2 Tabela de Evidências Reais

| Payload | ID Real | Status Pré-Retomada (Workers = 0) | Status Pós-Retomada (Workers = 2) | Criação (`createdAt`) | Início (`startedAt`) | Conclusão (`stoppedAt`) | Task do Worker |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `teste-01` | **2** | `new` (`stoppedAt: null`) | **`success`** | `02:23:38.785Z` | `02:24:39.445Z` | `02:24:49.497Z` | `621da0bd...` |
| `teste-02` | **3** | `new` (`stoppedAt: null`) | **`success`** | `02:23:39.352Z` | `02:24:39.464Z` | `02:24:49.506Z` | `621da0bd...` |
| `teste-03` | **4** | `new` (`stoppedAt: null`) | **`success`** | `02:23:39.940Z` | `02:24:39.480Z` | `02:24:45.479Z` | `621da0bd...` |

> [!IMPORTANT]
> **Comprovação Temporal de Retenção:** Entre a criação dos jobs (`02:23:39Z`) e o início do processamento pelos workers (`02:24:39Z`), decorreram aproximadamente **60 segundos de retenção na fila do Valkey**, com posterior processamento assíncrono bem-sucedido dos três jobs após a restauração da capacidade.

### 4.3 Ressalva Técnica sobre o Processamento dos Jobs

Os três jobs foram processados concorrentemente pelo mesmo Worker (`621da0bd...`).
- **Causa Técnica:** Como os workers operam com `--concurrency=5`, o primeiro worker a restabelecer a sessão com o Valkey possuía 5 threads ociosas, drenando os 3 jobs disponíveis da fila de uma única vez.
- **Conclusão:** O teste comprovou a **retenção e o processamento posterior dos três jobs** após a recuperação dos workers. Entretanto, **não comprovou alta disponibilidade completa de infraestrutura** (por residir em nó único de EC2 e Valkey Single-AZ) nem **balanceamento de carga entre múltiplos nós de worker**. Para demonstrar balanceamento entre workers distintos em testes futuros, recomenda-se submeter um volume de requisições superior à capacidade unitária (ex.: > 5 jobs simultâneos) ou fixar `--concurrency=1`.

---

## 5. Limitações Arquiteturais do Laboratório

A arquitetura implantada prioriza a viabilidade financeira para ambiente de estudo e validação. Para migração a um cenário de produção crítica, devem ser consideradas as seguintes melhorias:

1. **Host EC2 Único (SPOF Computacional):** Main e Workers residem na mesma máquina `t3.small`. Em caso de falha física do host, todas as tarefas param até a recuperação pelo ASG (~3 a 5 min). *Recomendação para produção:* Distribuir em pelo menos 2 hosts EC2 Multi-AZ ou adotar AWS Fargate Multi-AZ.
2. **ElastiCache Single-AZ:** Nó único sem réplica de leitura e sem failover automático (`AutomaticFailover: disabled`). *Recomendação para produção:* Habilitar Multi-AZ com réplica de leitura gerenciada.
3. **Margem Restrita de Memória:** Dos 1.913 MiB registrados no ECS, 1.550 MiB estão alocados em soft limits (Memory Reservations), restando **363 MiB de capacidade residual de agendamento do ECS** (e não memória RAM física livre). Workflows com manipulação de grandes volumes de dados podem atingir hard limits (800 MiB Main / 550 MiB Workers). *Recomendação para produção:* Dimensionar instâncias `t3.medium` (4 GB) ou superiores.

---

## 6. Procedimento de Limpeza dos Recursos (Teardown Controlado)

Para eliminar quaisquer custos residuais pós-validação, a desmontagem deve seguir estritamente a ordem de dependência reversa:

### Matriz de Recursos: Exclusão vs. Preservação

| Categoria | Recursos a EXCLUIR (Exclusivos do Desafio 6) | Recursos a PRESERVAR (Compartilhados com o BIA) |
|---|---|---|
| **Computação ECS** | Serviços `svc-n8n-worker` e `svc-n8n-main` | Cluster ECS da BIA (`cluster-bia-app`) |
| **Task Definitions** | Revisões `task-def-n8n-main` e `task-def-n8n-worker` | Task Definitions do projeto BIA |
| **Auto Scaling** | ASG `asg-n8n-d2n` e Launch Template `lt-n8n-d2n` | ASG e Launch Templates da BIA |
| **Cluster ECS** | Capacity Provider `cp-n8n-d2n` e Cluster `cluster-n8n-d2n` | Capacity Providers e Roles do BIA |
| **Balanceamento** | Listener HTTPS:443, ALB `n8n-d2n-alb` e Target Group `tg-n8n-d2n` | ALB `bia-cloud-alb` e Target Groups da BIA |
| **Fila e Cache** | Cluster ElastiCache `n8n-valkey` e Subnet Group `n8n-valkey-subgrp` | Nenhum (exclusivo do N8N) |
| **Banco de Dados** | RDS PostgreSQL `n8n` (`--skip-final-snapshot`) | Bancos de dados RDS da aplicação BIA |
| **DNS Route 53** | Somente o registro Alias A `n8n.bia.d2ns.com.br` | **PRESERVAR** Hosted Zone `Z0200626TQFMAZ5GPD92` e registros `bia.d2ns.com.br` |
| **Rede & Segurança** | SGs `n8n-valkey-sg`, `n8n-db`, `n8n-ec2` e `n8n-alb` | **PRESERVAR** VPC `vpc-093b15ec114bc9eb2`, Subnets, IGW, Route Tables e Certificado ACM `*.bia.d2ns.com.br` |
| **Logs e Segredos** | Log Group `/ecs/n8n-ec2` e Parâmetros `/n8n/*` (se não reutilizados) | Log Groups e parâmetros SSM da BIA |

### Ordem Sequencial de Desmontagem via AWS CLI

```bash
# 1. Reduzir e excluir os serviços ECS
aws ecs update-service --cluster cluster-n8n-d2n --service svc-n8n-worker --desired-count 0 --region us-east-2 --profile n8n-lab
aws ecs update-service --cluster cluster-n8n-d2n --service svc-n8n-main --desired-count 0 --region us-east-2 --profile n8n-lab
aws ecs delete-service --cluster cluster-n8n-d2n --service svc-n8n-worker --region us-east-2 --profile n8n-lab
aws ecs delete-service --cluster cluster-n8n-d2n --service svc-n8n-main --region us-east-2 --profile n8n-lab

# 2. Encerrar instâncias e excluir ASG
aws autoscaling update-auto-scaling-group --auto-scaling-group-name asg-n8n-d2n --min-size 0 --max-size 0 --desired-capacity 0 --region us-east-2 --profile n8n-lab
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name asg-n8n-d2n --force-delete --region us-east-2 --profile n8n-lab

# 3. Excluir Cluster ECS e Capacity Provider
aws ecs delete-capacity-provider --capacity-provider cp-n8n-d2n --region us-east-2 --profile n8n-lab
aws ecs delete-cluster --cluster cluster-n8n-d2n --region us-east-2 --profile n8n-lab

# 4. Excluir Launch Template
aws ec2 delete-launch-template --launch-template-id lt-0f379fbb524ea5793 --region us-east-2 --profile n8n-lab

# 5. Excluir ALB e Target Group
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:us-east-2:730972069864:loadbalancer/app/n8n-d2n-alb/4864a22397613b4a --region us-east-2 --profile n8n-lab
aws elbv2 delete-target-group --target-group-arn arn:aws:elasticloadbalancing:us-east-2:730972069864:targetgroup/tg-n8n-d2n/ae88c59f2e5de42a --region us-east-2 --profile n8n-lab

# 6. Excluir ElastiCache Valkey
aws elasticache delete-replication-group --replication-group-id n8n-valkey --region us-east-2 --profile n8n-lab
aws elasticache delete-cache-subnet-group --cache-subnet-group-name n8n-valkey-subgrp --region us-east-2 --profile n8n-lab

# 7. Excluir RDS PostgreSQL
aws rds delete-db-instance --db-instance-identifier n8n --skip-final-snapshot --delete-automated-backups --region us-east-2 --profile n8n-lab

# 8. Excluir exclusivamente o registro Route 53 n8n.bia.d2ns.com.br (PRESERVANDO a Hosted Zone)
# (via change-resource-record-sets com Action: DELETE)

# 9. Excluir Security Groups exclusivos
aws ec2 delete-security-group --group-id sg-0e566f84ab4a5d213 --region us-east-2 --profile n8n-lab # n8n-valkey-sg
aws ec2 delete-security-group --group-id sg-044556529fd601827 --region us-east-2 --profile n8n-lab # n8n-db
aws ec2 delete-security-group --group-id sg-04ecd5e6ca63859b5 --region us-east-2 --profile n8n-lab # n8n-ec2
aws ec2 delete-security-group --group-id sg-0583c7b790c7b7f45 --region us-east-2 --profile n8n-lab # n8n-alb

# 10. Excluir CloudWatch Log Group
aws logs delete-log-group --log-group-name /ecs/n8n-ec2 --region us-east-2 --profile n8n-lab
```
