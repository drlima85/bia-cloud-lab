# BIA Cloud Lab — Visão Geral e Arquitetura do Sistema

> [!NOTE]
> Este documento contém informações fictícias e simplificadas para demonstração de Retrieval-Augmented Generation (RAG). Os exemplos de arquitetura, modelos de dados e endpoints não representam necessariamente a implementação real da aplicação BIA Cloud Lab.

## 1. O que é o BIA Cloud Lab

O **BIA Cloud Lab** (Business Intelligence & Automation Cloud Laboratory) é uma aplicação moderna de gestão de tarefas e automação desenvolvida para demonstrar práticas de engenharia de software em nuvem utilizando a infraestrutura da **Amazon Web Services (AWS)**.

A aplicação foi desenhada seguindo os pilares do **AWS Well-Architected Framework**:
- **Excelência Operacional:** Logs estruturados, monitoramento e automação de deploys.
- **Segurança:** Isolamento de rede em VPC pública e privada, credenciais via IAM Roles e AWS Secrets Manager.
- **Confiabilidade:** Execução em contêineres resilientes com suporte a failover e réplicas de leitura.
- **Eficiência de Performance:** Camada de cache em memória para leituras frequentes e consultas otimizadas.
- **Otimização de Custos:** Dimensionamento baseado em consumo sob demanda e instâncias gerenciadas (Fargate).

---

## 2. Componentes da Solução

A arquitetura do BIA é composta por quatro camadas principais:

```
[ Usuário / Navegador ]
         │
         ▼
[ Application Load Balancer (ALB) ]
         │
         ├─► [ Frontend: React / Vite + Nginx ] (Porta 80)
         │
         └─► [ Backend API: Node.js / Express ] (Porta 3000)
                   │
                   ├─► [ Cache: Valkey / Redis (Amazon ElastiCache) ] (Porta 6379)
                   │
                   ├─► [ Banco de Dados: PostgreSQL (Amazon RDS) ] (Porta 5432)
                   │
                   └─► [ Inteligência Artificial: Amazon Bedrock ] (API us-east-1)
```

### 2.1 Frontend (Interface de Usuário)
- **Tecnologia:** Single Page Application (SPA) construída com React 18 e Vite.
- **Servidor Web:** Imagem Docker leve com Alpine Linux e Nginx como reverse proxy local.
- **Funcionalidades:** Listagem interativa de tarefas, filtros por status/prioridade, formulário de cadastro e assistente de IA integrado.

### 2.2 Backend (API REST)
- **Tecnologia:** Node.js (versão 20 LTS) com framework Express.
- **Autenticação e Sessão:** Tokens JWT com renovação controlada.
- **Comunicação com AWS:** AWS SDK for JavaScript v3 (clientes modulares).

### 2.3 Camada de Dados e Cache
- **PostgreSQL (RDS):** Armazenamento relacional primário para tarefas, usuários e logs de auditoria.
- **Valkey / Redis (ElastiCache):** Cache de consultas frequentes e gerenciamento de rate limiting.

### 2.4 Trilha de IA (Amazon Bedrock)
- **Modelos Homologados:** Família Anthropic Claude (Claude 3.5 Sonnet / Claude 3.7 Sonnet).
- **Recursos:** Converse API, Function Calling (Tools), RAG via Knowledge Bases e moderação via Guardrails.
