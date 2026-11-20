# Desafio 02 — N8N Queue Mode na AWS com Amazon ElastiCache Valkey

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** N8N na AWS (Plataforma de Automação & Workflows)<br>
> **Referência educacional:** Desafio 6 da Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Documentado e Estruturado (Evidência histórica homologada com testes de resiliência)<br>
> **Adaptações D2NS:** Desacoplamento distribuído entre instâncias Main (Webhooks) e Workers via fila BullMQ no Amazon ElastiCache Valkey, com validação empírica de resiliência e retenção de jobs.<br>
> **Laboratório Histórico Original:** [`n8n-lab/`](../../../n8n-lab/)

---

## 🎯 Objetivo Arquitetural

Evoluir a implantação do **N8N** na AWS do modelo monólito (*Single-Mode*) para uma arquitetura distribuída, escalável e desacoplada em fila (**Queue Mode**).

A solução desacopla a recepção de requisições externas e a interface gráfica do processamento pesado dos fluxos de trabalho, garantindo que picos massivos de tráfego em webhooks ou rotinas demoradas não comprometam a disponibilidade da plataforma nem a experiência do operador.

---

## 🗺️ Evolução Arquitetural: Desafio 01 vs. Desafio 02

| Dimensão Técnica | Desafio 01 (Single-Mode) | Desafio 02 (Queue Mode) |
|---|---|---|
| **Padrão Arquitetural** | Monólito em container único (UI + Execuções) | Desacoplado: 1 Main (UI/Webhooks) + 2 Workers em fila |
| **Message Broker** | Inexistente (execuções locais em memória) | **Amazon ElastiCache Valkey 7.2** com TLS e AUTH Token |
| **Capacidade Computacional** | 1 instância EC2 `t3.micro` (1 GB RAM) | 1 instância EC2 `t3.small` (2 GB RAM) via Capacity Provider |
| **Impacto de Sobrecarga** | Webhooks e interface travam sob carga pesada | Webhooks respondem instantaneamente; fila absorve picos |
| **Resiliência a Falhas** | Reinício do container interrompe recepção | Workers podem reiniciar/escalar sem derrubar o Main ou perder jobs |

---

## ⚙️ Componentes e Responsabilidades no Queue Mode

```
                                  Internet
                                     │
                                 HTTPS:443
                                     │
                     ┌───────────────▼───────────────┐
                     │    Route 53 (Alias A)         │ n8n.<SEU_DOMINIO>
                     │    ACM Wildcard RSA-2048      │ *.<SEU_DOMINIO>
                     └───────────────┬───────────────┘
                                     │
                     ┌───────────────▼───────────────┐
                     │ Application Load Balancer     │ Listener HTTPS:443
                     │ (Target Group Dinâmico)       │ Health check /healthz
                     └───────────────┬───────────────┘
                                     │ Dynamic Port Mapping
                                     ▼ (hostPort 32768-65535)
┌────────────────────────────────────┼────────────────────────────────────┐
│ Amazon EC2 Host (t3.small · AL2023 ECS Optimized · Modo Bridge)         │
│                                                                        │
│   ┌────────────────────────────────▼────────────────────────────────┐  │
│   │ ECS Service Main (svc-n8n-main · desiredCount: 1)               │  │
│   │ Task: UI + Webhooks + Scheduler (Porta 5678 -> Porta Dinâmica)  │  │
│   │ Soft Limit: 650 MiB · Hard Limit: 800 MiB                       │  │
│   └───────────────┬─────────────────────────────────┬───────────────┘  │
│                   │                                 │                  │
│                   │ Enfileira Job (TLS:6379)        │ Schemas (5432)   │
│                   ▼                                 ▼                  │
│   ┌────────────────────────────────┐ ┌──────────────────────────────┐  │
│   │ ECS Service Worker             │ │ Amazon RDS PostgreSQL 16.13  │  │
│   │ (svc-n8n-worker · desired: 2)  │ │ (db.t3.micro · Privado VPC)  │  │
│   │ Tasks: w1 e w2                 │ └──────────────▲───────────────┘  │
│   │ Soft: 450 MiB · Hard: 550 MiB  │                │                  │
│   │ Concurrency: 5 por task        │                │                  │
│   └───────────────┬────────────────┘                │                  │
│                   │                                 │                  │
│                   │ Drena Fila (TLS:6379 com AUTH)  │ Grava Execuções  │
│                   ▼                                 │                  │
│   ┌─────────────────────────────────────────────────┴───────────────┐  │
│   │ Amazon ElastiCache Valkey 7.2 (cache.t4g.micro · Replication Grp)│  │
│   │ 🔒 TLS Obrigatório + 🔑 AUTH Token via SSM Parameter Store     │  │
│   └─────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Serviço Main (`svc-n8n-main`):**
   - Executa a Task [`task-def-n8n-main`](templates/task-def-n8n-main.example.json).
   - Registrado no Target Group do ALB através de mapeamento dinâmico de portas.
   - Responsável pelo editor web, endpoints de webhook (`/webhook/*`), agendadores cron e enfileiramento das tarefas no message broker (`EXECUTIONS_MODE=queue`).
2. **Serviço Worker (`svc-n8n-worker`):**
   - Executa as Tasks [`task-def-n8n-worker`](templates/task-def-n8n-worker.example.json) com comando explícito `["worker", "--concurrency=5"]`.
   - **Sem portas mapeadas no host e sem registro no ALB.**
   - Consome continuamente a fila BullMQ hospedada no Valkey e grava os estados e resultados finais no Amazon RDS PostgreSQL.
3. **Message Broker (Amazon ElastiCache Valkey 7.2):**
   - Fork open-source de alta performance mantido pela Linux Foundation, totalmente compatível com o protocolo Redis OSS e a biblioteca BullMQ.
   - Provisionado em modo Replication Group de nó único (`cache.t4g.micro`), com criptografia em trânsito (TLS) e autenticação forte obrigatória (`AUTH Token`).
4. **Armazenamento de Segredos:**
   - Senha do banco (`/n8n/db_password`), chave de criptografia de credenciais (`/n8n/encryption_key`) e token do Valkey (`/n8n/valkey_token`) gerenciados via AWS Systems Manager Parameter Store (`SecureString`).

---

## 🧪 Resumo e Evidências dos Testes Históricos de Resiliência

> [!NOTE]
> **Registro de Execução Histórica:**<br>
> Os testes descritos a seguir foram executados e homologados na nuvem AWS durante a sessão de laboratório original (2026-11-09) e documentados em [`HISTORICO-SESSAO.md`](../../../n8n-lab/HISTORICO-SESSAO.md). Eles **não foram reexecutados nesta fase documental**.

### 1. Metodologia do Teste de Resiliência
Para comprovar o desacoplamento real entre a recepção das requisições e seu processamento, foi utilizado o workflow [`templates/workflow-resiliencia.example.json`](templates/workflow-resiliencia.example.json) com gatilho Webhook configurado no modo assíncrono `Immediately` (`responseMode: "onReceived"`).

### 2. Sequência de Falha Induzida e Retenção em Fila
1. **Parada Total dos Workers:** O serviço `svc-n8n-worker` foi escalado para `desiredCount=0`. Comprovou-se via AWS CLI que nenhuma task de worker permanecia ativa (`runningCount == 0`).
2. **Disparo de Requisições Externas:** Três chamadas POST consecutivas foram enviadas ao endpoint público (`teste-01`, `teste-02`, `teste-03`). Todas receberam **`HTTP/2 200 OK` instantaneamente** pelo ALB/Main.
3. **Auditoria de Retenção:**
   - **No PostgreSQL (`execution_entity`):** Os registros foram criados com status **`new`** e campos `startedAt: null` e `stoppedAt: null`.
   - **No ElastiCache Valkey:** A fila BullMQ (`bull:jobs:wait`) registrou exatamente `waitingJobsCount: 3` (`["4", "3", "2"]`).
4. **Recuperação da Capacidade:** O serviço `svc-n8n-worker` foi restaurado para `desiredCount=2`. As tarefas iniciaram, autenticaram no Valkey via TLS/AUTH e drenaram a fila pendente.

### 3. Matriz de Evidências Reais da Homologação

| Payload | ID de Execução | Status Pré-Retomada (Workers = 0) | Status Pós-Retomada (Workers = 2) | Tempo de Retenção na Fila | Status Final |
|:---:|:---:|:---:|:---:|:---:|:---:|
| `teste-01` | **2** | `new` (`startedAt: null`) | **`success`** | ~60 segundos | Processado com Sucesso |
| `teste-02` | **3** | `new` (`startedAt: null`) | **`success`** | ~60 segundos | Processado com Sucesso |
| `teste-03` | **4** | `new` (`startedAt: null`) | **`success`** | ~60 segundos | Processado com Sucesso |

### 4. Ressalva Técnica sobre o Processamento
- **Comportamento Observado:** Os 3 jobs foram processados concorrentemente pelo mesmo Worker. Como os workers operavam com `--concurrency=5`, o primeiro worker disponível possuía 5 threads ociosas, drenando a fila de uma só vez.
- **Conclusão Formal:** O teste comprovou com rigor a **retenção e posterior processamento assíncrono na fila**. Entretanto, por residir em uma máquina EC2 única (`t3.small`) e Valkey Single-AZ para otimização de custos de estudo, **não comprova alta disponibilidade de infraestrutura contra queda física de datacenter (Multi-AZ)** nem **balanceamento balanceado entre múltiplos nós de worker** (cenário que exigiria carga > 5 requisições simultâneas ou `--concurrency=1`).

---

## 📄 Templates Sanitizados Fornecidos

Neste desafio são fornecidos quatro modelos de configuração sanitizados:

1. **Task Definition do Main:**
   👉 [`templates/task-def-n8n-main.example.json`](templates/task-def-n8n-main.example.json) — UI, Webhooks, Dynamic Port Mapping e segredos SSM.
2. **Task Definition dos Workers:**
   👉 [`templates/task-def-n8n-worker.example.json`](templates/task-def-n8n-worker.example.json) — Processador assíncrono BullMQ com `--concurrency=5` e sem portas no host.
3. **Workflow de Teste de Resiliência:**
   👉 [`templates/workflow-resiliencia.example.json`](templates/workflow-resiliencia.example.json) — Definição JSON exportada com webhook assíncrono e atraso artificial de 2s.
4. **Variáveis de Ambiente do Laboratório:**
   👉 [`templates/env.example`](templates/env.example) — Relação completa de parâmetros para orquestração via CLI.

---

## 🛡️ Matriz de Classificação de Maturidade

| Componente / Recurso | Classificação de Estado | Detalhes da Validação |
|---|:---:|---|
| **Task Definition Main Sanitizada** | ✅ Implementado e Documentado | Template [`task-def-n8n-main.example.json`](templates/task-def-n8n-main.example.json) com portas dinâmicas e segredos SSM. |
| **Task Definition Worker Sanitizada** | ✅ Implementado e Documentado | Template [`task-def-n8n-worker.example.json`](templates/task-def-n8n-worker.example.json) com isolamento total de portas. |
| **Template de Workflow de Teste** | ✅ Implementado e Documentado | Template [`workflow-resiliencia.example.json`](templates/workflow-resiliencia.example.json) com resposta imediata em webhook. |
| **Template de Variáveis de Ambiente** | ✅ Implementado e Documentado | Modelo sanitizado [`env.example`](templates/env.example) para parametrização. |
| **Comprovação de Retenção em Fila** | 🔍 Evidenciado Historicamente | Homologação empírica de retenção de 3 jobs por 60s documentada na sessão original. |
| **Alta Disponibilidade Multi-AZ** | ⚪ Proposto para Produção | Requer dimensionamento em múltiplos nós EC2 e ElastiCache Multi-AZ com réplica. |
