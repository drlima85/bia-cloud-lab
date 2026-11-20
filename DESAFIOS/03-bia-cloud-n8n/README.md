# ⚡ Trilha: N8N na AWS (Plataforma de Automação & Workflows)

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** N8N na AWS (Automação de Workflows Empresariais)<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído e Validado na AWS (Ambiente de laboratório desmontado após conclusão dos testes)<br>

Estudo arquitetural e prático da implantação da plataforma de automação **N8N** na nuvem AWS, demonstrando a evolução de maturidade de engenharia de um modelo monólito (**Fase 1 — Desafio 5: Single-Mode com Auto-Recovery**) para uma arquitetura distribuída e desacoplada em fila (**Fase 2 — Desafio 6: Queue Mode com Amazon ElastiCache Valkey**).

---

## 📚 Atribuição e Origem

- **Projeto:** BIA Cloud Lab — D2NS
- **Programa de Referência:** Formação AWS, conduzida por [Henrylle Maia](https://www.linkedin.com/in/henrylle/).
- **Implementações e Adaptações:** Desenvolvidas e documentadas por **Danilo Lima — D2NS** a partir do laboratório original [`n8n-lab/`](../../n8n-lab/).
- **Adaptações D2NS:**
  - Evolução do modelo Single-Mode para Queue Mode desacoplado com Amazon ElastiCache Valkey (BullMQ).
  - Governança estrita de menor privilégio com 9 políticas IAM dedicadas e mapeadas por função.
  - Execução e homologação de teste empírico de retenção de jobs em fila durante parada forçada de workers.
  - Especificação consultiva de agente especialista em AWS DevOps para suporte à automação.
  - Parametrização defensiva de scripts utilitários de diagnóstico de conectividade para PostgreSQL e Valkey.
  - Planejamento orçamentário com eliminação de custos recorrentes de NAT Gateway.
- **Preservação do Histórico:** O diretório original [`n8n-lab/`](../../n8n-lab/) permanece preservado como histórico de laboratório e memorial técnico de execuções. A documentação consolidada e os templates sanitizados encontram-se estruturados nesta trilha.

---

## 🎯 Estrutura da Trilha e Navegação

```
DESAFIOS/03-bia-cloud-n8n/
├── README.md                                  # Visão geral da trilha e atribuições
├── 01-n8n-single-mode/                        # Desafio 5: N8N Single-Mode com Auto-Recovery
│   ├── README.md
│   └── templates/
│       └── task-def.example.json              # Template sanitizado da Task ECS Single-Mode
├── 02-n8n-queue-mode/                         # Desafio 6: N8N Queue Mode com ElastiCache Valkey
│   ├── README.md
│   └── templates/
│       ├── task-def-n8n-main.example.json     # Template sanitizado da Task Main (UI/Webhook)
│       ├── task-def-n8n-worker.example.json   # Template sanitizado da Task Worker (Processamento)
│       ├── workflow-resiliencia.example.json  # Workflow de homologação de resiliência
│       └── env.example                        # Variáveis de ambiente de referência
├── mcp/                                       # Ferramenta Operacional Complementar (AWS MCP)
│   └── README.md                              # Guia de observabilidade e auditoria via MCP
├── agents/                                    # Especificações Consultivas de Agentes
│   └── n8n/                                   # Agente Especialista AWS DevOps para N8N
│       ├── README.md                          # Diretrizes de governança e instruções de ativação
│       └── agent.md                           # Especificação técnica da persona
├── iam/                                       # Governança e Templates IAM Sanitizados
│   ├── README.md                              # Guia de governança, ordem e menor privilégio
│   ├── 01-policy-prevalidation-readonly.example.json
│   ├── 02-policy-deploy.example.json
│   ├── 03-trust-policy-ecs-tasks.example.json
│   ├── 04-inline-policy-execution-role.example.json
│   ├── 05-trust-policy-ec2.example.json
│   ├── 06-instance-role-managed-policies.example.json
│   ├── 07-instance-profile.example.json
│   ├── 08-policy-elasticache-valkey.example.json
│   └── 09-inline-policy-route53.example.json
├── docs/                                      # Memorial Arquitetural e Decisões
│   ├── architecture.md                        # Memorial comparativo Single vs Queue Mode
│   └── architecture-decisions.md              # Architecture Decision Records (ADRs 01 a 06)
└── scripts/                                   # Scripts Utilitários de Diagnóstico
    ├── README.md                              # Guia de diagnóstico, variáveis e execução segura
    ├── check-db.js                            # Diagnóstico de conectividade PostgreSQL (RDS)
    └── check-valkey.js                        # Diagnóstico de conectividade Valkey (BullMQ)
```

### Índice de Módulos

| Módulo / Desafio | Título | Estado | Foco Técnico |
|:---:|---|:---:|---|
| **Fase 1** | [01-n8n-single-mode](01-n8n-single-mode/README.md) | ✅ Concluído e Documentado | Desafio 5: Monólito N8N em container único com auto-recovery (self-healing) local. |
| **Fase 2** | [02-n8n-queue-mode](02-n8n-queue-mode/README.md) | ✅ Concluído e Documentado | Desafio 6: Desacoplamento de UI/Webhooks e processamento assíncrono em fila BullMQ. |
| **MCP** | [mcp/](mcp/README.md) | ✅ Concluído e Documentado | Ferramenta complementar: observabilidade e auditoria segura via AWS MCP Server. |
| **Agente** | [agents/n8n/](agents/n8n/README.md) | 📐 Especificação Consultiva | Modelo de governança do agente especialista AWS DevOps para N8N. |
| **IAM** | [iam/](iam/README.md) | ✅ Concluído e Documentado | Governança de identidades, 9 templates de menor privilégio e ordem de dependências. |
| **Docs** | [docs/architecture.md](docs/architecture.md) | ✅ Concluído e Documentado | Memorial técnico consolidado, topologias de rede, limites e ADRs arquiteturais. |
| **Scripts** | [scripts/](scripts/README.md) | ✅ Concluído e Documentado | Utilitários de diagnóstico de conectividade para PostgreSQL e Valkey/BullMQ. |

---

## 🗺️ Comparativo dos Padrões Arquiteturais e Escopo de Resiliência

O projeto aborda duas etapas distintas de arquitetura, demonstrando como desacoplar responsabilidades em sistemas distribuídos:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       Evolução Arquitetural do N8N na AWS                       │
├──────────────────────────────────────┬──────────────────────────────────────────┤
│    Fase 1 — Desafio 5 (Single-Mode)  │     Fase 2 — Desafio 6 (Queue Mode)      │
├──────────────────────────────────────┼──────────────────────────────────────────┤
│ • 1 Task ECS única (Monólito)        │ • 1 Task Main (UI + Recepção de Webhooks)│
│ • UI, Webhooks e Execuções juntos    │ • 2 Tasks Workers (Processamento Pesado) │
│ • Execuções gerenciadas em memória   │ • Message Broker Amazon ElastiCache      │
│ • Host EC2 t3.micro (1 GB RAM)       │ • Host EC2 t3.small (2 GB RAM)           │
│ • Sobrecarga pode degradar webhooks  │ • Webhook responde instantaneamente      │
│ • Recuperação via restart da task    │ • Fila retém jobs durante paradas/picos  │
│ • Sem tolerância entre zonas         │ • Tolerante a falhas de workers locais   │
└──────────────────────────────────────┴──────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Esclarecimento Técnico sobre Alta Disponibilidade e Topologia Single-AZ:**<br>
> A infraestrutura física implementada neste laboratório operou em **Single-AZ** (Zona de Disponibilidade `2b`) com instâncias `t3.micro` / `t3.small` e banco Amazon RDS Single-AZ para conter os custos da conta de treinamento.<br>
> - **O que foi comprovado no laboratório:** O ambiente entrega **Recuperação Automática Local (Self-Healing)** contra falhas de container (reinício automático pelo ECS) e de instância (substituição pelo Auto Scaling Group), além de **Resiliência de Fila** (retenção de mensagens durante paradas temporárias dos workers).<br>
> - **O que NÃO deve ser confundido com Alta Disponibilidade Real:** A topologia Single-AZ **não é tolerante à perda de um datacenter ou zona inteira da AWS**.<br>
> - **Arquitetura Proposta para Produção (Multi-AZ):** A extensão para alta disponibilidade real corporativa é documentada em [`docs/architecture.md`](docs/architecture.md), contemplando RDS Multi-AZ com failover síncrono, cluster ECS distribuído em múltiplas sub-redes privadas e Auto Scaling horizontal de workers baseado em métricas de profundidade de fila no CloudWatch.

---

## ☁️ Recursos AWS Envolvidos na Trilha

- **Amazon ECS com EC2:** Cluster gerenciado (`cluster-n8n-d2n`) operando com Capacity Provider e Auto Scaling Group (AMI AL2023 ECS-Optimized).
- **Rede e Dynamic Port Mapping:** Containers executando em modo `bridge` com porta dinâmica (`hostPort: 0 -> containerPort: 5678`), viabilizando acesso de saída à internet pelo IP público da EC2 **sem custo de NAT Gateway** (~$32/mês de economia).
- **Application Load Balancer (ALB):** Ponto de entrada seguro com terminação HTTPS (porta 443), certificado wildcard ACM e health check em `/healthz`.
- **Amazon ElastiCache Valkey 7.2:** Message broker open-source compatível com Redis e BullMQ, configurado com **criptografia TLS em trânsito** e autenticação obrigatória via **AUTH Token**.
- **Amazon RDS PostgreSQL 16.13:** Banco relacional dedicado em sub-rede privada da VPC para persistência de workflows, credenciais e histórico de execuções.
- **AWS Systems Manager (SSM) Parameter Store:** Parâmetros `SecureString` criptografados via KMS para injeção segura de credenciais em tempo de inicialização das Tasks via ECS Agent.
- **Amazon CloudWatch Logs:** Centralização de telemetria dos containers Main e Worker com retenção configurável.

---

## 🛠️ Recursos Operacionais e Ferramental Complementar

### 1. AWS Model Context Protocol (MCP) — Observabilidade e Auditoria
A trilha integra o protocolo MCP em [`mcp/`](mcp/README.md) como ferramenta complementar de apoio à engenharia. O servidor MCP opera sob perfil dedicado com permissões estritas de somente leitura (*Read-Only*), permitindo que agentes de IA e o CLI inspecionem clusters, serviços ECS e Target Groups do ALB sem intervenções diretas ou exposição de credenciais estáticas.

### 2. Agente Especializado em AWS DevOps
Em [`agents/n8n/`](agents/n8n/README.md), é disponibilizada a especificação consultiva do agente de governança DevOps. O agente orienta a execução segura dos desafios, impondo aprovação humana mandatória para comandos destrutivos, controle rigoroso de custos e conformidade com o princípio de menor privilégio.

### 3. Scripts Utilitários de Diagnóstico
Na pasta [`scripts/`](scripts/README.md), encontram-se utilitários Node.js parametrizados para validação prévia de conectividade antes da inicialização dos contêineres:
- `check-db.js`: Valida conectividade TCP, autenticação e credenciais SSL com o Amazon RDS PostgreSQL.
- `check-valkey.js`: Valida handshake TLS e autenticação AUTH Token com o Amazon ElastiCache Valkey (BullMQ).

---

## 🛡️ Decisões de Governança e Boas Práticas

1. **Expurgo de Segredos e Placeholders Estritos:** Nenhum template versionado neste repositório contém identificadores reais de contas AWS, senhas ou tokens privados. Todos utilizam `<SUA_CONTA_AWS>`, `<SEU_ENDPOINT_RDS_POSTGRES>`, `<SEU_ENDPOINT_ELASTICACHE_VALKEY>` e `<SEU_DOMINIO>`.
2. **Menor Privilégio IAM:**
   - **Task Execution Role:** Permissão restrita de leitura no SSM Parameter Store (`/n8n/*`) e escrita no CloudWatch Logs.
   - **Container Runtime Seguro:** O container N8N opera sem Task Role associada, impedindo que workflows executem chamadas arbitrárias à AWS API sem credenciais explícitas configuradas nos nós.
   - **Instance Profile EC2:** Permissões restritas ao ECS Agent (`AmazonEC2ContainerServiceforEC2Role`) e acesso seguro via **SSM Session Manager** (`AmazonSSMManagedInstanceCore`), eliminando necessidade de portas SSH abertas (TCP 22) ou chaves `.pem`.
3. **Gestão Orçamentária e Desprovisionamento:**
   - Os recursos de laboratório com tarifação contínua por hora (instâncias EC2, nós de ElastiCache Valkey e banco RDS) foram planejados para desmontagem após a homologação das evidências, assegurando custo zero em inatividade.

---

## 📊 Matriz Factual: Execução Real versus Arquitetura Proposta

| Componente / Desafio | Status Factual | Detalhes Técnicos e Evidências |
|---|:---:|---|
| **Fase 1: Single-Mode (Desafio 5)** | ✅ Executado e documentado | Monólito ECS EC2 com container `n8nio/n8n`, porta dinâmica em modo `bridge` e RDS dedicado. Template em [`01-n8n-single-mode/templates/task-def.example.json`](01-n8n-single-mode/templates/task-def.example.json). |
| **Fase 2: Queue Mode (Desafio 6)** | ✅ Executado e documentado | Separação Main/Worker, ElastiCache Valkey 7.2 com TLS e BullMQ. Templates em [`02-n8n-queue-mode/templates/`](02-n8n-queue-mode/templates/). |
| **Teste de Resiliência de Fila** | 🔍 Evidenciado historicamente | Homologado na AWS em 2026-11-10: retenção comprovada de 3 jobs (`POST /webhook/teste-resiliencia`) durante parada forçada dos workers (`desiredCount=0`), com consumo e sucesso posterior após o restabelecimento do serviço. |
| **Governança IAM (9 Políticas)** | ✅ Validado sintaticamente | 9 templates declarativos de menor privilégio auditados em [`iam/`](iam/README.md). |
| **Observabilidade via AWS MCP** | ✅ Documentado e estruturado | Integração consultiva em modo Read-Only documentada em [`mcp/README.md`](mcp/README.md). |
| **Agente DevOps N8N** | 📐 Especificação consultiva | Modelo de governança documentado em [`agents/n8n/README.md`](agents/n8n/README.md). |
| **Scripts de Diagnóstico** | ✅ Validado sintaticamente | Utilitários parametrizados e documentados em [`scripts/README.md`](scripts/README.md). |
| **Alta Disponibilidade Multi-AZ** | 💡 Arquitetura proposta | Modelo concebido para produção em [`docs/architecture.md`](docs/architecture.md); não implementado no laboratório para contenção de custos. |
