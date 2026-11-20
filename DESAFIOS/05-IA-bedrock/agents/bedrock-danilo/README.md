# 🤖 Agente Personalizado: `bedrock-danilo`

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** 📐 Especificação Consultiva Modelada<br>
> **Adaptações D2NS:** Modelagem de agente especialista em runtime Node.js ESM, checkpoints em streaming, tool use defensivo, RAG com threshold e moderação com Guardrails para o ambiente D2NS.

Especificação e documentação do agente especialista em **Amazon Bedrock e Inteligência Artificial Generativa**, modelado para dar suporte técnico e operacional aos seis desafios da trilha `05-IA-bedrock` no **BIA Cloud Lab**.

---

## 📚 Origem e Inspiração

- **Projeto:** BIA Cloud Lab — D2NS
- **Referência educacional:** Inspirado na modelagem de agentes do repositório Colorado (`.kiro/agents/curso-bedrock.json`), utilizado no curso de Amazon Bedrock da **Formação AWS**, ministrado por **Henrylle Maia**.
- **Implementação e adaptações:** Reestruturado por **Danilo Lima — D2NS** para atender especificamente aos experimentos, scripts Node.js com checkpoints, integrações RAG e políticas de Guardrails desenvolvidas no BIA Cloud Lab.

---

## 🧠 Capacidades e Escopo Técnico

O agente `bedrock-danilo` foi projetado para:

1. **Apoio ao Chat Conversacional e Streaming:** Compreender o ciclo de vida de requisições à API Converse e ConverseStream do Bedrock, auxiliando na depuração de rotinas assíncronas e gravação periódica de checkpoints (`03-bedrock-chat`).
2. **Engenharia de Ferramentas (Tool Use):** Auxiliar na definição de schemas JSON de ferramentas locais e no tratamento defensivo dos argumentos retornados pelo modelo (`04-bedrock-tools`).
3. **Arquiteturas RAG:** Apoiar na avaliação de relevância semântica (cálculo de threshold/score mínimo), curadoria de bases documentais e integração com Amazon Bedrock Knowledge Bases gerenciadas (`05-rag-knowledge-base`).
4. **Governança com Guardrails:** Orientar a criação de filtros de conteúdo e moderação de respostas para mitigação sistemática de alucinações e proteção contra vazamento de PII (`06-guardrails`).
5. **Consulta Automatizada via MCP:** Utilizar o servidor MCP `awslabs.aws-documentation-mcp-server` para embasar decisões em documentações oficiais e atualizadas da AWS.

---

## ⚙️ Relação com o Ecossistema de Agentes

> [!IMPORTANT]
> **Status de Ativação:** Este arquivo representa uma **especificação consultiva** mantida dentro da trilha `05-IA-bedrock`.<br>
> O agente `bedrock-danilo` **NÃO está ativo globalmente** na raiz do projeto (`.agents/` ou `.kiro/`), garantindo que o agente existente de automação (agente local `.agents/agents/n8n/agent.md`) permaneça 100% isolado e sem conflitos.

### Instruções Consultivas para Ativação Futura (AGY)

Caso deseje ativar este agente no **Antigravity CLI (AGY)** em uma fase futura:

1. Copiar a pasta `agents/bedrock-danilo/` para a raiz de agentes do projeto:
   ```bash
   cp -r DESAFIOS/05-IA-bedrock/agents/bedrock-danilo .agents/agents/
   ```
2. Adicionar o servidor de documentação MCP ao arquivo de configuração local `.agents/mcp_config.json` na raiz, conforme o modelo em [`mcp/aws-docs-mcp.example.json`](../../mcp/aws-docs-mcp.example.json).
3. O agente estará disponível no CLI sob a persona `bedrock-danilo`.
