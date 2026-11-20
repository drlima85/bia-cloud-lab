# Desafio 03 — Chat Conversacional e Streaming com Bedrock

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Suporte a streaming de respostas assíncrono via ConverseStream, prompt caching para redução de custos e implementação de rotina de checkpoint a cada 5 minutos.

---

## 🎯 Objetivo Arquitetural

Implementar interfaces conversacionais interativas com modelos fundacionais no Amazon Bedrock, cobrindo tanto chamadas básicas via AWS CLI quanto aplicações em Node.js com suporte a resposta em tempo real via **streaming** e otimização de latência/custo com **prompt caching**.

---

## ☁️ Serviços, Tecnologias e Dependências

- **Amazon Bedrock:** Anthropic Claude 3 / 3.5 (Sonnet / Haiku) e perfis de inferência cross-region (região oficial: `us-east-1` — Norte da Virgínia).
- **AWS CLI:** Comandos `aws bedrock-runtime converse` e scripts Shell interativos.
- **Node.js (ESM):** Node.js >= 18 com `@aws-sdk/client-bedrock-runtime` e `@aws-sdk/credential-providers`.
- **Utilitários de Sistema (VM Ubuntu):** `bash` (>= 4.0) e `jq` para manipulação de payloads JSON.

---

## 📜 Scripts Migrados e Objetivos

> [!NOTE]
> Os scripts de execução utilizados neste laboratório não fazem parte da versão pública deste repositório. A documentação técnica permanece disponível para consulta e estudo.

### Interface CLI (Shell Scripts em `cli/`)
| Arquivo | Objetivo Técnico |
|---|---|
| `v1-basico-lab-danilo.sh` | Chatbot básico via CLI com `Converse API` concentrando comportamento e contexto no system prompt. |
| `v2-user-message-lab-danilo.sh` | Separação semântica entre comportamento do assistente (system) e mensagem dinâmica do usuário (user). |
| `v3-prompt-externo-lab-danilo.sh` | Carga de system prompt a partir de arquivo externo reutilizável com resolução via `SCRIPT_DIR`. |
| `v4-loop-interativo-lab-danilo.sh` | Loop conversacional contínuo no terminal mantendo histórico completo de turnos com `jq`. |

### SDK Node.js (Aplicações ESM em `sdk/`)
| Arquivo | Objetivo Técnico |
|---|---|
| `v4-loop-interativo.mjs` | Chat conversacional interativo via `ConverseCommand` com AWS SDK v3 e histórico em memória. |
| `v5-streaming.mjs` | Resposta em tempo real via streaming com `ConverseStreamCommand` e prompt caching (1h). |
| `v5-streaming-checkpoint.mjs` | Streaming conversacional com persistência periódica de checkpoints de sessão em JSON. |
| `v5-streaming-5min.mjs` | Streaming com checkpoints automatizados e gerenciamento de timeout de inatividade (5 min). |

---

## ⚙️ Variáveis de Ambiente e Configurações

| Variável | Obrigatória | Padrão | Descrição |
|---|:---:|:---:|---|
| `AWS_PROFILE` | Sim (Shell) | `default` (Node) | Perfil com credenciais configurado no `~/.aws/credentials`. |
| `MODEL_ID` | Sim (Shell) | Definido no script (Node) | ID ou inference profile do modelo Bedrock (ex.: `us.anthropic.claude-sonnet-4-5-20250929-v1:0`). |
| `REGION` | Não | `us-east-1` | Região AWS de execução da chamada de inferência. |
| `PROMPT_PATH` | Não | Automático | Caminho absoluto ou relativo para um arquivo de prompt customizado. |
| `PROMPT_FILE` | Não | `prompt-valendo-Danilo.txt` | Nome do prompt padrão localizado em `../../shared/prompts/`. |

---

## 💻 Instruções de Execução na VM Ubuntu

> [!NOTE]
> Os exemplos abaixo utilizam perfis e identificadores genéricos. Nenhum comando realiza chamadas à rede sem credenciais válidas configuradas previamente.

### 1. Execução dos Scripts Shell (`cli/`)
```bash
# Navegar até a pasta do desafio
cd ~/formacaoaws/bia-cloud-lab/DESAFIOS/05-IA-bedrock/03-bedrock-chat/cli

# Definir as variáveis de ambiente necessárias
export AWS_PROFILE="seu-profile"
export MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0"

# Opcional: ajustar região ou apontar para prompt específico
export REGION="us-east-1"
export PROMPT_PATH="../../shared/prompts/prompt-valendo-Danilo.txt"

# Executar o script desejado
bash v1-basico-lab-danilo.sh
bash v4-loop-interativo-lab-danilo.sh
```

### 2. Execução das Aplicações Node.js (`sdk/`)
```bash
# Navegar até a pasta SDK
cd ~/formacaoaws/bia-cloud-lab/DESAFIOS/05-IA-bedrock/03-bedrock-chat/sdk

# Definir o perfil AWS de execução
export AWS_PROFILE="seu-profile"

# Executar o chat interativo ou streaming
node v4-loop-interativo.mjs
node v5-streaming.mjs
```

---

## 🌐 Recursos Externos Necessários

- **Model Access no Amazon Bedrock:** Acesso liberado para a família Claude 3 / 3.5 Sonnet ou Haiku na região `us-east-1` via console AWS.
- **Permissões IAM:** Permissão `bedrock:InvokeModel` e `bedrock:InvokeModelWithResponseStream` associadas ao perfil configurado.

---

## 📋 Status e Validação de Evidências

- **Estado:** ✅ Concluído.
- **Implementações Realizadas:**
  - Scripts CLI de conversação em loop (`v1-basico.sh` a `v4-loop-interativo.sh`).
  - Aplicações Node.js implementando leitura assíncrona por chunks de streaming e gravação de histórico de checkpoints a cada intervalo de sessão.
- **Evidências Registradas:** Execução confirmada no repositório de laboratório Colorado (`scripts/sdk-node-danilo/v4-loop-interativo.mjs` e `v5-streaming*.mjs`).

---

## 🔗 Relação com a Aplicação Core

Base para implementação de assistentes de suporte ou chatbots integrados ao frontend ou painel administrativo da BIA.
