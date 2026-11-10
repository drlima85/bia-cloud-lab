# Diagrama da Arquitetura — Desafio 6: N8N Queue Mode

Este documento consolida a representação visual da arquitetura implantada, validada e homologada no planejamento [`n8n-ha-queue-mode-v3.0.md`](n8n-ha-queue-mode-v3.0.md).

> [!TIP]
> **Versão Gráfica Interativa em HTML:**  
> Uma visualização gráfica vetorial (SVG) com layout oficial da AWS está disponível no arquivo local [`n8n-queue-mode-architecture.html`](n8n-queue-mode-architecture.html).

---

## 1. Legenda de Status dos Recursos

- 🔵 **Recursos Compartilhados / Preexistentes:** Recursos de rede e governança da conta AWS compartilhados com o ecossistema BIA (`vpc-093b15ec114bc9eb2`, certificado ACM `*.bia.d2ns.com.br`, Hosted Zone Route 53 `Z0200626TQFMAZ5GPD92`).
- 🟢 **Recursos Implantados e Validados (100% Ativos):** Todos os componentes exclusivos do N8N Queue Mode provisionados, conectados e auditados com sucesso nas Etapas 1 a 12.

---

## 2. Diagrama de Fluxo e Topologia de Rede (Mermaid)

```mermaid
flowchart TD
    %% Nós Externos
    User([Usuário / Webhook Externo])
    
    %% Borda e Serviços Globais
    subgraph Borda ["Borda e Resolução DNS (Região us-east-2)"]
        R53["🟢 Route 53 (Hosted Zone: Z0200626TQFMAZ5GPD92)<br/>n8n.bia.d2ns.com.br (Alias A · INSYNC)"]
        ACM["🔵 AWS Certificate Manager<br/>*.bia.d2ns.com.br (Status: ISSUED)"]
        SSM["🟢 SSM Parameter Store<br/>/n8n/valkey_token<br/>/n8n/db_password<br/>/n8n/encryption_key"]
        CW["🟢 CloudWatch Logs<br/>/ecs/n8n-ec2 (Retenção: 7 dias)<br/>streams: n8n-main e n8n-worker"]
    end

    %% Camada VPC
    subgraph VPC ["🔵 VPC: vpc-093b15ec114bc9eb2 (CIDR 172.31.0.0/16)"]
        subgraph Subnets ["🔵 Subnets Multi-AZ: subnet-0aef2d36da47e89e9 (2a) e subnet-0c9a226c460d77c8f (2b)"]
            
            %% Balanceamento de Carga
            subgraph LoadBalancing ["Camada de Entrada HTTP/HTTPS"]
                ALB["🟢 ALB: n8n-d2n-alb<br/>DNS: n8n-d2n-alb-706987622.us-east-2.elb.amazonaws.com<br/>SG: sg-0583c7b790c7b7f45 (n8n-alb)<br/>Listener HTTPS:443 (HTTP/2)"]
                TG["🟢 Target Group: tg-n8n-d2n<br/>type: instance · path: /healthz · delay: 30s<br/>Target: i-09f7979988ba3b9b7 (Porta Dinâmica, ex. 32769 no teste · healthy)"]
            end

            %% Camada de Computação ECS
            subgraph ECS_Host ["Host EC2 ECS (t3.small · i-09f7979988ba3b9b7 · SG: sg-04ecd5e6ca63859b5 · 1.913 MiB total · 363 MiB folga de agendamento)"]
                subgraph ECS_Cluster ["🟢 ECS Cluster: cluster-n8n-d2n (Capacity Provider: cp-n8n-d2n)"]
                    
                    subgraph SvcMainGroup ["🟢 SERVICE: svc-n8n-main (desiredCount: 1 · running: 1)"]
                        TaskMain["Task Main (task-def-n8n-main:1)<br/>• Soft Limit: 650 MiB (Hard: 800 MiB)<br/>• Dynamic Port Mapping: hostPort efêmera (ex. 32769 no teste) -> container 5678<br/>• Papel: UI, Editor, Webhook, Timers<br/>• EXECUTIONS_MODE=queue<br/>• OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true"]
                    end

                    subgraph SvcWorkerGroup ["🟢 SERVICE: svc-n8n-worker (desiredCount: 2 · running: 2)"]
                        TaskW1["Task Worker w1 (task-def-n8n-worker:1)<br/>• Soft Limit: 450 MiB (Hard: 550 MiB)<br/>• command: ['worker', '--concurrency=5']<br/>• Sem portas expostas / Sem ALB"]
                        TaskW2["Task Worker w2 (task-def-n8n-worker:1)<br/>• Soft Limit: 450 MiB (Hard: 550 MiB)<br/>• command: ['worker', '--concurrency=5']<br/>• Sem portas expostas / Sem ALB"]
                    end

                end
            end

            %% Camada de Mensageria e Dados
            subgraph DadosMensageria ["Camada de Dados Persistentes e Fila"]
                Valkey[("🟢 ElastiCache Valkey: n8n-valkey<br/>Endpoint: master.n8n-valkey.hkfaul.use2.cache.amazonaws.com:6379<br/>• Engine: Valkey 7.2 (cache.t4g.micro Single-AZ 2b)<br/>• 🔒 TLS Ativado + 🔑 AUTH Token Ativo<br/>• SG: sg-0e566f84ab4a5d213 (n8n-valkey-sg)")]
                
                RDS[("🟢 RDS PostgreSQL: n8n<br/>Endpoint: n8n.ctekugasc68m.us-east-2.rds.amazonaws.com:5432<br/>• Engine: PostgreSQL 16.13 (db.t3.micro, 20 GB gp2)<br/>• Acesso Público: false (Privado na VPC)<br/>• SG: sg-044556529fd601827 (n8n-db)")]
            end

        end
    end

    %% Conexões e Fluxos
    User -->|1. HTTPS:443| R53
    R53 -->|2. Roteamento Alias A| ALB
    ACM -.->|Certificado SSL Wildcard| ALB
    ALB -->|3. Forward HTTP/2| TG
    TG -->|4. Dynamic Port Mapping (Porta Efêmera, ex. 32769)| TaskMain

    TaskMain -.->|5. Enfileira Execução (BullMQ) via TLS:6379 com AUTH| Valkey
    TaskMain -->|6. Lê/Escreve Schemas e Metadados via TLS TCP:5432| RDS

    TaskW1 -.->|7. Drena Jobs via TLS:6379 com AUTH| Valkey
    TaskW2 -.->|7. Drena Jobs via TLS:6379 com AUTH| Valkey

    TaskW1 -->|8. Executa Workflow e Grava Status via TLS TCP:5432| RDS
    TaskW2 -->|8. Executa Workflow e Grava Status via TLS TCP:5432| RDS

    SSM -.->|Injeção de Segredos em Runtime| TaskMain
    SSM -.->|Injeção de Segredos em Runtime| TaskW1
    SSM -.->|Injeção de Segredos em Runtime| TaskW2

    TaskMain -.->|Logs| CW
    TaskW1 -.->|Logs| CW
    TaskW2 -.->|Logs| CW
```

---

## 3. Matriz de Componentes e Status Efetivo de Implementação

| Componente | Nome Identificador | Status Efetivo | Categoria | Papel na Arquitetura |
|---|---|---|---|---|
| **VPC** | `vpc-093b15ec114bc9eb2` | Ativo | 🔵 Compartilhado | Rede isolada com subnets públicas em `us-east-2a` e `us-east-2b`. |
| **Certificado ACM** | `*.bia.d2ns.com.br` | `ISSUED` | 🔵 Compartilhado | Terminação segura HTTPS (porta 443) no ALB com validação pública. |
| **Route 53** | `Z0200626TQFMAZ5GPD92` | **`INSYNC`** | 🟢 Provisionado | Registro Alias A para `n8n.bia.d2ns.com.br` apontando para o ALB. |
| **Segredos SSM** | `/n8n/*` | **Disponível** | 🟢 Provisionado | Senhas do banco, chave de encriptação e AUTH token do Valkey. |
| **Security Groups** | `n8n-alb`, `n8n-ec2`, `n8n-db`, `n8n-valkey-sg` | **Disponível** | 🟢 Provisionado | Isolamento de tráfego na VPC seguindo menor privilégio. |
| **RDS PostgreSQL** | `n8n` (`db.t3.micro`) | **`available`** | 🟢 Provisionado | Banco relacional persistente (`16.13`), não público na porta 5432. |
| **ElastiCache Valkey** | `n8n-valkey` (`cache.t4g.micro`) | **`available`** | 🟢 Provisionado | Message broker BullMQ (`valkey 7.2`) com TLS e AUTH na porta 6379. |
| **Target Group** | `tg-n8n-d2n` | **`healthy`** | 🟢 Provisionado | Tipo instance, HTTP:5678, path `/healthz`, dynamic port mapping (porta efêmera, ex. `32769` observada no teste). |
| **ALB** | `n8n-d2n-alb` | **`active`** | 🟢 Provisionado | Application Load Balancer internet-facing na porta HTTPS 443. |
| **Launch Template** | `lt-n8n-d2n` (`t3.small`) | **Ativo** | 🟢 Provisionado | Template EC2 com AL2023 ECS AMI e auto-registro no cluster. |
| **Auto Scaling Group** | `asg-n8n-d2n` | **`InService`** | 🟢 Provisionado | 1 instância `t3.small` (`i-09f7979988ba3b9b7`, 1.913 MiB RAM). |
| **ECS Cluster** | `cluster-n8n-d2n` | **`ACTIVE`** | 🟢 Provisionado | Cluster ECS com Capacity Provider strategy `cp-n8n-d2n`. |
| **CloudWatch Logs** | `/ecs/n8n-ec2` | **Ativo** | 🟢 Provisionado | Retenção 7 dias; streams `n8n-main` e `n8n-worker`. |
| **Task Defs** | `task-def-n8n-main:1` e `worker:1` | **`ACTIVE`** | 🟢 Provisionado | Especificações em modo `bridge` com limites de memória validados. |
| **ECS Services** | `svc-n8n-main` e `svc-n8n-worker` | **`ACTIVE`** | 🟢 Provisionado | 1 task Main (ALB) e 2 tasks Workers (fila) operacionais. |
