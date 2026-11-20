# 🧠 Trilha: Amazon Bedrock & IA Generativa

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído (6 Desafios Validados)<br>

Laboratórios práticos de Inteligência Artificial Generativa na AWS com foco no **Amazon Bedrock**, abordando engenharia de prompts, chamadas de inferência por CLI e SDK, ferramentas externas, bases de conhecimento vetoriais e moderação segura.

## 📚 Atribuição, Origem e Direitos

- **Projeto:** BIA Cloud Lab — D2NS
- **Referência educacional:** Conteúdo educacional do curso de Amazon Bedrock da **Formação AWS**, ministrado por [Henrylle Maia](https://www.linkedin.com/in/henrylle/).
- **Implementação e adaptações:** Desenvolvidas por **Danilo Lima — D2NS** (projeto Colorado / BIA Cloud Lab).
- **Adaptações D2NS:** Migração para ESM/Node.js nativo, implementação de gravação periódica de checkpoints de streaming a cada 5 minutos, injeção defensiva de tools com tratamento de exceções, RAG curado com score mínimo e políticas de moderação ética com Amazon Bedrock Guardrails.
- **Restrições de uso e redistribuição:** Todos os direitos sobre as estruturas conceituais de ensino e documentações proprietárias pertencem aos seus autores originais. Este material destina-se exclusivamente para estudo pessoal, portfólio técnico e validação de engenharia no BIA Cloud Lab — D2NS, sendo estritamente vedada a comercialização ou redistribuição pública não autorizada de materiais didáticos exclusivos da Formação AWS.

---

## 🎯 Índice dos Desafios

| Desafio | Título | Estado | Foco Técnico |
|---|---|:---:|---|
| **01** | [01-multi-agentic](01-multi-agentic/README.md) | ✅ Concluído | Modelagem e colaboração entre múltiplos agentes especializados. |
| **02** | [02-orchestration-mcp](02-orchestration-mcp/README.md) | ✅ Concluído | Orquestração de contexto e ferramentas via Model Context Protocol (MCP). |
| **03** | [03-bedrock-chat](03-bedrock-chat/README.md) | ✅ Concluído | Chat interativo via CLI e SDK Node.js com streaming e prompt caching. |
| **04** | [04-bedrock-tools](04-bedrock-tools/README.md) | ✅ Concluído | Tool Use / Function Calling para integração com sistemas externos. |
| **05** | [05-rag-knowledge-base](05-rag-knowledge-base/README.md) | ✅ Concluído | RAG com embeddings locais e Amazon Bedrock Knowledge Bases gerenciadas. |
| **06** | [06-guardrails](06-guardrails/README.md) | ✅ Concluído | Filtros éticos, proteção contra dados sensíveis e mitigação de alucinação. |

---

## 🛠️ Tecnologias, Dependências e SDKs

- **Modelos:** Anthropic Claude (v3 Sonnet / Haiku / Claude 3.5), Amazon Titan Embeddings v2.
- **Serviços AWS:** Amazon Bedrock (Converse API e streaming), Knowledge Bases for Bedrock, Amazon S3, Amazon Bedrock Guardrails.
- **Runtime e Pacotes Node.js (ESM):**
  - Node.js >= 18 (Type: `module`)
  - `@aws-sdk/client-bedrock-runtime`
  - `@aws-sdk/client-bedrock-agent-runtime`
  - `@aws-sdk/credential-providers`
- **Utilitários do Sistema (VM Ubuntu):**
  - `aws-cli` v2 (configurado com profile e região `us-east-1`)
  - `jq` (>= 1.6) para parsing e composição de mensagens JSON
  - `bash` (>= 4.0)

---

## 🌐 Região AWS e Governança de Ambiente

- **Região Oficial da Trilha Bedrock:** `us-east-1` (Norte da Virgínia).
  - Esta é a região de referência para todos os laboratórios de IA Generativa da Formação AWS, assegurando acesso a todos os modelos fundacionais (Anthropic Claude, Amazon Titan), inference profiles cross-region, Knowledge Bases e Guardrails.
- **Configuração de Ambiente dos Scripts:**
  - **Scripts Shell (`cli/` e `06-guardrails/`):** Utilizam `REGION="${REGION:-us-east-1}"` como padrão, permitindo substituição sob demanda via exportação da variável `REGION` no terminal (ex.: `export REGION=us-west-2`).
  - **Scripts Node.js (`sdk/`, `tools/`, `rag/`, `guardrails/`):** Operam com `us-east-1` como região padrão dos clientes `@aws-sdk/client-bedrock-runtime` e `@aws-sdk/client-bedrock-agent-runtime`.
- **Isolamento Regional no BIA Cloud Lab:**
  - A definição de `us-east-1` aplica-se estritamente à trilha **Amazon Bedrock & IA Generativa**.
  - As demais trilhas de laboratório do repositório (Infraestrutura AWS, Elastic Beanstalk, N8N e Estratégias de Deploy) podem adotar regiões diferentes (como `sa-east-1` ou `us-east-1`) de acordo com suas arquiteturas específicas, mantendo escopos regionais completamente desacoplados.

---

## ⚙️ Tabela Consolidada de Variáveis de Ambiente

| Variável | Escopo | Obrigatória | Padrão | Descrição |
|---|---|:---:|:---:|---|
| `AWS_PROFILE` | Shell e Node | Sim (Shell) / Opcional (Node) | `default` (Node) | Perfil AWS configurado no arquivo `~/.aws/credentials`. |
| `MODEL_ID` | Shell | Sim (Shell) | Definido no código (Node) | ID do modelo fundacional no Bedrock (ex.: `us.anthropic.claude-sonnet-4-5-20250929-v1:0`). |
| `REGION` | Shell e Node | Não | `us-east-1` | Região da chamada de inferência e dos serviços de IA. |
| `PROMPT_PATH` | Shell e Node | Não | Automático | Caminho absoluto ou relativo para um arquivo de prompt customizado. |
| `PROMPT_FILE` | Shell e Node | Não | `prompt-exemplo.txt` | Nome do arquivo de prompt padrão localizado em `shared/prompts/`. |
| `KB_ID` | Node (RAG / Guardrails) | Sim (ao executar RAG) | `SEU_KNOWLEDGE_BASE_ID` | ID da Knowledge Base criada no Amazon Bedrock. |
| `GUARDRAIL_ID` | Node (Guardrails) | Sim (ao executar Guardrails) | `SEU_GUARDRAIL_ID` | ID do Guardrail criado no Amazon Bedrock. |
| `GUARDRAIL_VERSION` | Node (Guardrails) | Não | `DRAFT` | Versão da política do Guardrail (`DRAFT` ou número da versão). |

---

## 🔧 Como configurar seu ambiente

> [!NOTE]
> O arquivo [`.env.example`](.env.example) serve como documentação de referência das variáveis suportadas. Os scripts **não utilizam bibliotecas como `dotenv` nem carregam arquivos `.env` automaticamente**. Todas as variáveis devem ser exportadas diretamente na sua sessão de terminal ou passadas no comando de execução.

### 1. Requisitos Prévios
- **Node.js:** Versão 18 ou superior (`node -v`).
- **AWS CLI:** Versão 2 configurada (`aws --version`).
- **Dependências do Projeto:** Instalar na pasta da trilha (`cd DESAFIOS/05-IA-bedrock && npm install`) quando for executar testes funcionais com credenciais ativas.

### 2. Configuração do Perfil AWS Local (Sem Credenciais no Código)
Nunca insira chaves de acesso (`AWS_ACCESS_KEY_ID` ou `AWS_SECRET_ACCESS_KEY`) em scripts ou arquivos de configuração. Configure o perfil via AWS CLI:
```bash
aws configure --profile SEU_PERFIL_AWS
```
Se estiver utilizando credenciais temporárias (AWS SSO / Identity Center ou AWS Academy / Labs):
```bash
aws sso login --profile SEU_PERFIL_AWS
# ou exporte as credenciais temporárias da sessão diretamente no terminal
```

### 3. Definição das Variáveis no Terminal Ubuntu
Exporte as variáveis básicas para a sua sessão antes de executar os laboratórios:
```bash
export AWS_PROFILE="SEU_PERFIL_AWS"
export REGION="us-east-1"
export MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

### 4. Como Identificar o MODEL_ID no Amazon Bedrock
Para consultar os modelos fundacionais e inference profiles ativos na sua conta na região `us-east-1`:
```bash
aws bedrock list-inference-profiles --region us-east-1 --query "inferenceProfileSummaries[].[inferenceProfileId,inferenceProfileName]" --output table
```
Ou listar foundation models disponíveis:
```bash
aws bedrock list-foundation-models --region us-east-1 --by-provider anthropic --query "modelSummaries[].[modelId,modelName]" --output table
```
Copie o ID do modelo desejado (ex.: `us.anthropic.claude-sonnet-4-5-20250929-v1:0` ou `anthropic.claude-3-5-sonnet-20240620-v1:0`) e atribua à variável `MODEL_ID`.

### 5. Como Identificar KB_ID e GUARDRAIL_ID (Recursos Gerenciados)
Quando for executar os desafios de RAG (05) ou Guardrails (06):
- **Knowledge Base ID (`KB_ID`):**
  ```bash
  aws bedrock-agent list-knowledge-bases --region us-east-1 --query "knowledgeBaseSummaries[].[knowledgeBaseId,name,status]" --output table
  ```
  Exporte o ID alfanumérico retornado (ex.: `export KB_ID="SEU_KNOWLEDGE_BASE_ID"`).
- **Guardrail ID (`GUARDRAIL_ID`):**
  ```bash
  aws bedrock list-guardrails --region us-east-1 --query "guardrails[].[id,name,status]" --output table
  ```
  Exporte o ID retornado (ex.: `export GUARDRAIL_ID="SEU_GUARDRAIL_ID"`). A versão padrão adotada é `DRAFT` (`export GUARDRAIL_VERSION="DRAFT"`).

### 6. Uso do Prompt Público Padrão
Por padrão, todos os scripts da trilha utilizam o prompt público fictício temático do BIA Cloud Lab:
[`shared/prompts/prompt-exemplo.txt`](shared/prompts/prompt-exemplo.txt)
Nenhuma configuração adicional é necessária para utilizar esse prompt padrão.

### 7. Informando um Prompt Personalizado via PROMPT_PATH ou PROMPT_FILE
A resolução do prompt segue a seguinte ordem de precedência (em Shell e Node.js):
1. `PROMPT_PATH`: Caminho absoluto ou relativo informado.
2. `PROMPT_FILE`: Nome do arquivo resolvido dentro de `shared/prompts/`.
3. Padrão: `shared/prompts/prompt-exemplo.txt`.

Exemplos de uso:
```bash
# Opção 1: Caminho customizado completo (PROMPT_PATH)
export PROMPT_PATH="/caminho/para/seu-prompt-customizado.txt"

# Opção 2: Utilizando o prompt original mantido localmente (PROMPT_PATH)
export PROMPT_PATH="../../shared/prompts/prompt-valendo-Danilo.txt"

# Opção 3: Selecionando arquivo dentro de shared/prompts/ (PROMPT_FILE)
export PROMPT_FILE="prompt-valendo-Danilo.txt"
```

### 8. Desafios e Recursos AWS Necessários
| Desafio | Scripts | Recursos AWS Prévios Necessários |
|---|---|---|
| **03-bedrock-chat** | CLI e SDK Node.js | Modelo com acesso habilitado no Amazon Bedrock (`us-east-1`). |
| **04-bedrock-tools** | `v6-primeira-tool-danilo.mjs` | Modelo Claude habilitado para Converse API / Tool Calling. Base de dados da tool é simulada em memória. |
| **05-rag-knowledge-base** | `v7-rag-danilo.mjs`<br>`v7-rag-curado-danilo.mjs`<br>`v8-rag-managed-danilo.mjs` | Requer **Knowledge Base** ativa no Bedrock vinculada a um bucket S3 de dados e Vector Store (OpenSearch Serverless ou S3 Vectors). Necessário exportar `KB_ID`. |
| **06-guardrails** | `v7a` e `v7b` (Shell)<br>`v9-guardrail-danilo.mjs` (Node) | `v7a` e `v7b` necessitam apenas do modelo. `v9` requer **Guardrail** ativo no Bedrock (`GUARDRAIL_ID`) e opcionalmente uma **Knowledge Base** (`KB_ID`). |

---

## 💻 Guia de Execução Segura a partir da VM Ubuntu

> [!NOTE]
> Os exemplos a seguir utilizam perfis e parâmetros fictícios para garantir execução segura e sem exposição de credenciais.

### 1. Preparação do Ambiente
```bash
# Navegar até a raiz da trilha Bedrock
cd ~/formacaoaws/bia-cloud-lab/DESAFIOS/05-IA-bedrock

# Exportar perfil e modelo (obrigatórios para os scripts Shell)
export AWS_PROFILE="SEU_PERFIL_AWS"
export MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

### 2. Executando Desafios CLI
```bash
# Chat básico e loop interativo
bash 03-bedrock-chat/cli/v1-basico-lab-danilo.sh
bash 03-bedrock-chat/cli/v4-loop-interativo-lab-danilo.sh

# Comparativo de alucinação e contenção
bash 06-guardrails/v7a-prompt-alucinando-lab-danilo.sh
bash 06-guardrails/v7b-prompt-corrigido-lab-danilo.sh
```

### 3. Executando Desafios Node.js
```bash
# Chat conversacional e streaming
node 03-bedrock-chat/sdk/v4-loop-interativo.mjs
node 03-bedrock-chat/sdk/v5-streaming.mjs

# Function calling / Tool use
node 04-bedrock-tools/v6-primeira-tool-danilo.mjs

# RAG com Knowledge Bases (definir KB_ID previamente)
export KB_ID="SEU_KNOWLEDGE_BASE_ID"
node 05-rag-knowledge-base/v7-rag-danilo.mjs
node 05-rag-knowledge-base/v8-rag-managed-danilo.mjs

# Guardrails integrados (definir GUARDRAIL_ID previamente)
export GUARDRAIL_ID="SEU_GUARDRAIL_ID"
node 06-guardrails/v9-guardrail-danilo.mjs
```
