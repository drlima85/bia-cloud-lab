# Desafio 5 — Implantação do N8N na AWS

**Projeto:** BIA Cloud Lab AWS  
**Módulo:** Desafio 5 — Orquestração e Deploy do N8N em Nuvem  
**Região AWS:** `us-east-2` (Ohio)  
**Versão do N8N:** `n8nio/n8n:2.22.6` (Docker Hub, x86_64)  
**Status:** Implantação concluída e validada  

---

## 1. Visão Geral da Solução

O objetivo do **Desafio 5** é implantar a plataforma de automação de fluxos de trabalho **N8N** na AWS com a arquitetura padrão homologada pelo instrutor da Formação AWS. A solução adota um modelo **Single-Mode com Auto-Recovery (Self-Healing)**, otimizado para custo de laboratório e eficiência operacional, integrando:

* **Amazon ECS** com capacidade baseada em instâncias **Amazon EC2** (`t3.micro`).
* **Modo de rede `bridge`** com **Dynamic Port Mapping** (`containerPort: 5678` mapeada para portas efêmeras 32768–65535 no host).
* **Application Load Balancer (ALB)** público com terminação segura **HTTPS:443** e certificado digital ACM wildcard.
* **Target Group** do tipo `instance`, registrando a porta dinâmica do host alocada pelo ECS Agent para entrega do tráfego.
* **Banco de dados relacional dedicado Amazon RDS PostgreSQL** (PostgreSQL 16, `db.t3.micro`, 20 GB gp2).
* **Domínio próprio** roteado via **Amazon Route 53** sob `n8n.bia.d2ns.com.br`.
* **Segurança de credenciais** utilizando o **AWS Systems Manager (SSM) Parameter Store** com parâmetros `SecureString`.

---

## 2. Arquitetura e Decisões Técnicas

### 2.1 Modelo Arquitetural: Single-Mode com Auto-Recovery
Este ambiente de laboratório prioriza **baixo custo contínuo sem comprometer a resiliência operacional básica**:
* **Sem NAT Gateway:** O container utiliza o modo de rede `bridge`, aproveitando o IP público associado à instância EC2 para tráfego de saída à internet (execução de nós HTTP, APIs externas e webhooks).
* **Recuperação Automática de Container:** Se a aplicação falhar, o serviço ECS detecta o encerramento do container e sobe uma nova task na mesma instância (tempo de recuperação estimado em ~30–60 segundos).
* **Auto-Recovery de Host:** Caso a instância EC2 sofra falha física ou operacional, o Auto Scaling Group (ASG) encerra o host defeituoso, instancia uma nova máquina AL2023 ECS-Optimized (distribuída entre as AZs `us-east-2a` e `us-east-2b`), registra o host no cluster e inicia a Task do N8N (tempo de recuperação estimado em ~3–5 minutos).

### 2.2 Matriz de Decisões Técnicas

| Componente | Decisão Técnica | Justificativa |
|---|---|---|
| **Runtime ECS** | EC2 (`t3.micro`) | Menor custo em comparação ao Fargate para operação ininterrupta de laboratório. |
| **Modo de Rede** | `bridge` | Permite tráfego de saída à internet via IP público do host EC2 sem cobrança de NAT Gateway. |
| **Port Mapping** | Dinâmico (`hostPort: 0`, `containerPort: 5678`) | O container escuta na porta interna 5678 e o ECS Agent aloca portas efêmeras (32768–65535) no host EC2. |
| **Target Group** | Tipo `instance`, Dynamic Port Mapping | Registra dinamicamente a porta efêmera do host EC2 alocada pelo ECS para entrega na porta 5678 do container; `deregistration_delay: 30s` para drenagem rápida de conexões. |
| **Health Check** | Path `/healthz` (HTTP 200) | Endpoint nativo de health check da API do N8N avaliado na porta mapeada pelo ALB. |
| **Load Balancer** | ALB `n8n-d2n-alb` (HTTPS:443) | Terminação SSL pública utilizando certificado wildcard existente `*.bia.d2ns.com.br`. |
| **Banco de Dados** | RDS PostgreSQL (`db.t3.micro`, 20 GB gp2) | Instância dedicada `n8n`, Single-AZ (`us-east-2a`), sem acesso público, retenção de backup 0. |
| **SSL do Banco** | `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` | Mantém criptografia em trânsito (TLS), mas desabilita a validação da cadeia do certificado raiz do PostgreSQL, sendo uma configuração específica do laboratório para simplificação operacional (sem injeção de pacotes CA no container). |
| **Imagem N8N** | `n8nio/n8n:2.22.6` | Versão homologada pelo instrutor para arquitetura x86_64. |
| **Memória da Task** | `memoryReservation: 650` MiB | Soft limit viável dentro dos ~916 MiB utilizáveis da instância `t3.micro`. |
| **DNS** | Registro A (Alias) no Route 53 | Apontamento de baixa latência para o DNS do Application Load Balancer. |
| **Segredos** | SSM Parameter Store (`SecureString`) | Senha do RDS e chave de criptografia armazenadas sob criptografia KMS padrão (`alias/aws/ssm`). |

---

## 3. Diagrama da Arquitetura

```
                            Internet
                               │
                           HTTPS:443
                               │
               ┌───────────────▼───────────────┐
               │    ALB: n8n-d2n-alb           │ (Internet-Facing)
               │    SG:  n8n-alb (TCP 443)     │ Subnets: us-east-2a / 2b
               │    ACM: *.bia.d2ns.com.br     │
               └───────────────┬───────────────┘
                               │
                     Porta Dinâmica TCP
                     (ex: 32768..65535)
                               │
               ┌───────────────▼───────────────┐
               │    EC2 Host (t3.micro)        │ SG: n8n-ec2
               │    VPC Default (IP Público)   │ Inbound: ALB SG apenas
               │  ┌─────────────────────────┐  │
               │  │ Container N8N (Bridge)  │  │
               │  │ porta interna: 5678     │  │
               │  └────────────┬────────────┘  │
               └───────────────┼───────────────┘
                               │
                        TLS / TCP 5432
                               │
               ┌───────────────▼───────────────┐
               │  RDS PostgreSQL: n8n          │ SG: n8n-db
               │  (db.t3.micro, Não Público)   │ Inbound: n8n-ec2 SG apenas
               └───────────────────────────────┘
```

---

## 4. Recursos Provisionados e Evidências Reais

Todos os recursos foram implantados com sucesso na região `us-east-2`:

| Recurso AWS | Identificador / Nome | Especificação Técnica | Status |
|---|---|---|---|
| **Route 53** | `n8n.bia.d2ns.com.br` | Alias A record apontando para o ALB | `INSYNC` / Ativo |
| **Certificado ACM** | `*.bia.d2ns.com.br` | Wildcard RSA-2048 (Recurso Compartilhado) | `ISSUED` |
| **Application Load Balancer** | `n8n-d2n-alb` | Internet-facing, subnets públicas 2a e 2b | `active` |
| **Target Group** | `tg-n8n-d2n` | Tipo `instance`, Dynamic Port Mapping (containerPort 5678), delay 30s, health check `/healthz` | `healthy` (HTTP 200) |
| **ECS Cluster** | `cluster-n8n-d2n` | Cluster EC2 com Capacity Provider | `ACTIVE` |
| **Auto Scaling Group** | `asg-n8n-d2n` | `min=1`, `max=1`, `desired=1` | `InService` |
| **Launch Template** | `lt-n8n-d2n` | AL2023 ECS AMI, `t3.micro`, auto-registro | Ativo |
| **Task Definition** | `task-def-n8n-d2n` | `n8nio/n8n:2.22.6`, modo `bridge`, 650 MiB soft limit | `ACTIVE` |
| **ECS Service** | `svc-n8n-d2n` | Capacity Provider Strategy (`cp-n8n-d2n`, weight=1) | Steady State (1/1 tasks) |
| **CloudWatch Logs** | `/ecs/n8n-ec2` | Log stream dedicado da task N8N | Ativo |
| **RDS PostgreSQL** | Instância `n8n` | Engine 16.13, `db.t3.micro`, 20 GB gp2, não público | `available` |
| **SSM Parameter Store** | `/n8n/db_password`, `/n8n/encryption_key` | Segredos com criptografia `SecureString` | Ativos |

---

## 5. Estrutura do Diretório `n8n-lab/`

O projeto organiza seus arquivos separando com rigor o conteúdo público dos arquivos operacionais e confidenciais:

```
n8n-lab/
├── README.md                              # Documentação técnica completa da solução (este arquivo)
├── .env.example                           # Template sanitizado de variáveis de ambiente
├── task-definition.json                   # Template sanitizado da Task Definition do ECS
├── n8n-ha-single-mode-v2.1.md             # Especificação arquitetural de referência (sanitizada)
├── docs/                                  # Guias de governança e acesso IAM (sanitizados)
│   ├── acesso.md                          # Guia detalhado de permissões e ciclo de vida IAM
│   └── README-acesso.md                   # Resumo e ordem de execução das políticas IAM
├── .agents/                               # Especificações do agente e ferramentas (sanitizadas)
│   └── agents/
│       ├── agent.md                       # Diretrizes, papel e escopo do agente N8N DevOps
│       └── mcp_config.json                # Configuração do MCP server AWS para o agente
│
│── [ARQUIVOS OPERACIONAIS LOCAIS — NÃO PUBLICADOS / GITIGNORE]
├── .env                                   # Credenciais reais, IDs de recursos e ARNs de infraestrutura
├── HISTORICO-SESSAO.md                    # Registro cronológico detalhado de execução e diagnóstico
├── task-definition.operational.json       # Task Definition operacional original com ARNs reais
├── n8n-ha-single-mode-v2.1.operational.md # Planejamento operacional original com IDs reais da conta
├── *.bak                                  # Backups locais de segurança e versões anteriores
└── iam/                                   # Políticas IAM gerenciadas e trust policies locais
```

---

## 6. Governança e Segurança

1. **Coexistência e Recursos Compartilhados:** A infraestrutura de computação, banco de dados e segredos (ECS, RDS e SSM) foi provisionada de forma dedicada sob o prefixo `n8n-*`, preservando os recursos da aplicação principal (`bia-*`). O certificado digital ACM wildcard (`*.bia.d2ns.com.br`) e a Hosted Zone do Route 53 (`bia.d2ns.com.br`) são recursos compartilhados preexistentes que foram estritamente preservados durante o laboratório, recebendo apenas o novo registro do subdomínio `n8n`.
2. **Proteção de Segredos:** Credenciais e chaves de criptografia jamais foram expostas em código versionado, logs de execução ou terminal, sendo gerenciadas exclusivamente via SSM Parameter Store e arquivos `.env` locais com permissões estritas `600`.
3. **Menor Privilégio:** As Roles IAM associadas à Task Execution (`n8n-task-execution-role`) e à Instância EC2 (`n8n-ec2-instance-role`) foram criadas com políticas restritas às suas necessidades de execução e coleta de métricas/logs.
4. **Proteção no Git:** Todas as pastas operacionais locais (`iam/`, `.env`, `HISTORICO-SESSAO.md`, backups `.bak`, arquivos `*.operational.*`) são permanentemente ignoradas pelas regras de `.gitignore`.

---

## 7. Encerramento do Laboratório e Desmontagem da Infraestrutura

Para evitar custos recorrentes na conta AWS após o término dos testes e homologação do Desafio 5, a infraestrutura deverá ser excluída de forma controlada.

A desmontagem futura dos recursos seguirá a ordem estrita de desprovisionamento:
1. **ECS Service:** Atualizar `desiredCount=0` e excluir o serviço `svc-n8n-d2n`.
2. **Task Definition:** Desregistrar as revisões da `task-def-n8n-d2n`.
3. **Auto Scaling Group e EC2:** Reduzir capacidade mínima, desejada e máxima para 0 e excluir o ASG `asg-n8n-d2n`.
4. **Capacity Provider e Launch Template:** Desassociar e remover `cp-n8n-d2n` e excluir `lt-n8n-d2n`.
5. **ECS Cluster:** Excluir o cluster `cluster-n8n-d2n`.
6. **Application Load Balancer e Target Group:** Excluir o listener HTTPS 443, o ALB `n8n-d2n-alb` e o Target Group `tg-n8n-d2n`.
7. **RDS PostgreSQL:** Excluir a instância de banco de dados `n8n` (com `skip-final-snapshot`).
8. **Route 53:** Remover exclusivamente o registro A (Alias) `n8n.bia.d2ns.com.br` da Hosted Zone compartilhada, preservando os demais registros da BIA.
9. **Security Groups:** Excluir na sequência: `n8n-db`, `n8n-ec2` e `n8n-alb`.
10. **CloudWatch Logs e SSM:** Excluir o Log Group `/ecs/n8n-ec2` e os parâmetros `/n8n/db_password` e `/n8n/encryption_key`.
11. **Limpeza IAM:** Executar os comandos de desanexação e exclusão das roles e políticas detalhados no [Guia Operacional IAM](docs/README-acesso.md).

> [!NOTE]
> Todos os identificadores e ARNs necessários para a desmontagem automatizada encontram-se registrados no arquivo local `.env`. A exclusão só será executada mediante autorização formal.
