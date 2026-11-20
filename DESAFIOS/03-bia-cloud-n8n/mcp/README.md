# AWS Model Context Protocol (MCP) — Integração e Observabilidade do N8N na AWS

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Plataforma de Automação N8N na AWS (Ferramenta Operacional Complementar)<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Documentado e Estruturado<br>
> **Adaptações D2NS:** Integração operacional do Amazon ECS via AWS MCP Server para monitoramento, inspeção e governança da automação em modo somente leitura (Read-Only).

---

## 🎯 Objetivo Arquitetural e Operacional

Integrar o protocolo **Model Context Protocol (MCP)** ao ecossistema do **N8N na AWS** como ferramenta operacional de suporte ao engenheiro de nuvem.

O servidor MCP permite que agentes de IA e o CLI interajam de forma controlada com a infraestrutura do Amazon ECS, Application Load Balancer e logs do CloudWatch, operando sob uma política estrita de somente leitura (*Read-Only*) e menor privilégio, eliminando a necessidade de expor credenciais estáticas no terminal.

---

## ☁️ Serviços e Tecnologias

- **AWS Model Context Protocol (MCP Server):** Interface padronizada (JSON-RPC) para consulta e auditoria de recursos AWS via LLMs e assistentes locais.
- **Amazon ECS (EC2):** Inspeção de status de clusters, serviços e tasks do N8N sem comandos manuais ad-hoc.
- **Application Load Balancer (ALB):** Auditoria de saúde de target groups e roteamento seguro de portas dinâmicas.
- **AWS IAM & Menor Privilégio:** Perfil dedicado `n8n-lab` operando com a política de pré-validação somente leitura [`iam/01-policy-prevalidation-readonly.example.json`](../iam/01-policy-prevalidation-readonly.example.json).

---

## 🛡️ Governança e Boas Práticas Operacionais

1. **Operação Exclusiva em Modo Read-Only:** O MCP nesta trilha foi restrito a ações de consulta e diagnóstico (`Describe*`, `Get*`, `List*`), impedindo alterações acidentais ou destrutivas na infraestrutura.
2. **Isolamento de Credenciais:** Operação com perfil nomeado (`AWS_PROFILE=n8n-lab`) sem inclusão de credenciais em arquivos versionados.
3. **Complementaridade:** O MCP não substitui a definição de infraestrutura (Task Definitions, IAM roles e scripts de inicialização), atuando como acelerador de observabilidade e auditoria.

---

## 📋 Status e Validação de Evidências

- **Estado:** ✅ Documentado e Estruturado.
- **Implementações Realizadas:** Mapeamento de permissões de leitura, configuração do proxy MCP e validação de comandos de inspeção de tarefas do ECS e logs operacionais.
- **Evidências Registradas:** Auditoria histórica documentada no planejamento de infraestrutura do laboratório.
