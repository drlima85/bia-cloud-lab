# Desafio 06 — Amazon Bedrock Guardrails

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Configuração de filtros éticos e de moderação de conteúdo, mascaramento automático de PII (dados sensíveis) e testes práticos de mitigação de alucinação no ambiente D2NS.

---

## 🎯 Objetivo Arquitetural

Estabelecer barreiras de segurança (*guardrails*) e governança sobre as interações com modelos de IA generativa, assegurando filtragem de conteúdo inadequado, mascaramento de informações pessoalmente identificáveis (PII), bloqueio de tópicos proibidos e redução sistemática de alucinações.

---

## ☁️ Serviços, Tecnologias e Dependências

- **Amazon Bedrock Guardrails:** Políticas de proteção configuradas na AWS (região oficial: `us-east-1` — Norte da Virgínia).
- **Node.js (ESM):** Node.js >= 18 com `@aws-sdk/client-bedrock-runtime`, `@aws-sdk/client-bedrock-agent-runtime` e `@aws-sdk/credential-providers`.
- **AWS CLI e Shell:** `bash` (>= 4.0), `jq` e `aws-cli` v2 configurados na VM Ubuntu.

---

## 📜 Scripts Migrados e Objetivos

> [!NOTE]
> Os scripts de execução utilizados neste laboratório não fazem parte da versão pública deste repositório. A documentação técnica permanece disponível para consulta e estudo.

### Scripts Shell (`.sh`)
| Arquivo | Objetivo Técnico |
|---|---|
| `v7a-prompt-alucinando-lab-danilo.sh` | Demonstra a vulnerabilidade a alucinações de modelos fundacionais quando submetidos a perguntas fora de escopo sem regras explícitas de grounding ou constraints. |
| `v7b-prompt-corrigido-lab-danilo.sh` | Demonstra a contenção de alucinações no nível do prompt através de regras rígidas de restrição (*constraints*), ancoragem (*grounding*) e resposta padrão de contingência (*fallback*). |

### Aplicação Node.js (`.mjs`)
| Arquivo | Objetivo Técnico |
|---|---|
| `v9-guardrail-danilo.mjs` | Integração da API Converse com Amazon Bedrock Guardrails gerenciado (`guardrailConfig`). Avalia e bloqueia proativamente intervenções de segurança, dados sensíveis (PII) e tópicos negados em conjunto com RAG e Tools. |

---

## ⚙️ Variáveis de Ambiente e Configurações

| Variável | Obrigatória | Padrão | Descrição |
|---|:---:|:---:|---|
| `AWS_PROFILE` | Sim (Shell) / Não (Node) | `default` (Node) | Perfil configurado no `~/.aws/credentials`. |
| `MODEL_ID` | Sim (Shell) | Definido no script (Node) | ID do modelo Bedrock utilizado para inferência. |
| `REGION` | Não | `us-east-1` | Região AWS do Bedrock e Guardrails. |
| `GUARDRAIL_ID` | Sim (Node v9) | `SEU_GUARDRAIL_ID` | Identificador único do Guardrail criado no Amazon Bedrock. |
| `GUARDRAIL_VERSION` | Não | `DRAFT` | Versão do Guardrail (`DRAFT` ou versão numérica ex.: `"1"`). |
| `KB_ID` | Sim (Node v9) | `SEU_KB_ID` | Identificador do Knowledge Base para fluxo integrado. |
| `PROMPT_PATH` | Não | Automático | Caminho customizado para o arquivo de prompt. |
| `PROMPT_FILE` | Não | `prompt-valendo-Danilo.txt` | Nome do prompt carregado a partir de `../shared/prompts/`. |

---

## 💻 Instruções de Execução na VM Ubuntu

### 1. Testes Comparativos de Alucinação (Shell CLI)
```bash
# Navegar até a pasta do desafio
cd ~/formacaoaws/bia-cloud-lab/DESAFIOS/05-IA-bedrock/06-guardrails

# Definir as variáveis de ambiente necessárias
export AWS_PROFILE="seu-profile"
export MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0"

# Executar o cenário sem proteção (alucina)
bash v7a-prompt-alucinando-lab-danilo.sh

# Executar o cenário protegido por prompt engineering (mitiga)
bash v7b-prompt-corrigido-lab-danilo.sh
```

### 2. Execução da Aplicação com Guardrail Ativo (Node.js)
```bash
# Definir parâmetros do Guardrail e do KB
export AWS_PROFILE="seu-profile"
export GUARDRAIL_ID="gr-1234567890ab"
export GUARDRAIL_VERSION="DRAFT"
export KB_ID="ABC123XYZ4"

# Executar a aplicação
node v9-guardrail-danilo.mjs
```

---

## 🌐 Recursos Externos e Políticas de Segurança AWS

- **Amazon Bedrock Guardrail Ativo:** Política criada na região `us-east-1` contendo:
  - Filtros de moderação de conteúdo (ódio, insultos, violência).
  - Tópicos proibidos (*Denied Topics*).
  - Mascaramento ou bloqueio de informações pessoais identificáveis (*PII* como CPF, RG, cartão de crédito).
- **Permissões IAM:** `bedrock:ApplyGuardrail`, `bedrock:InvokeModel` e `bedrock:Retrieve`.

---

## 📋 Status e Validação de Evidências

- **Estado:** ✅ Concluído.
- **Implementações Realizadas:** Script em Node.js (`v9-guardrail-danilo.mjs`) que envia requisições com avaliação de guardrail ativa, registrando intervenções e bloqueios quando políticas de segurança são acionadas.
- **Evidências Registradas:** Testes comparativos documentados entre prompts com risco de alucinação e prompts corrigidos via filtros e instruções negativas no laboratório Colorado.

---

## 🔗 Relação com a Aplicação Core

Garante que qualquer interação pública ou interna assistida por IA dentro do ecossistema BIA respeite regras de conformidade e segurança da informação.
