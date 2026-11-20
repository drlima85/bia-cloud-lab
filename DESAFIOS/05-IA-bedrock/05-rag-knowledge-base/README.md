# Desafio 05 — RAG e Amazon Bedrock Knowledge Bases

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Curadoria e sanitização de base documental pública da BIA, implementação de cálculo de threshold/score mínimo de similaridade vetorial e integração com Knowledge Bases gerenciadas.

---

## 🎯 Objetivo Arquitetural

Implementar a arquitetura de **Retrieval-Augmented Generation (RAG)** para enriquecer as respostas do modelo com dados proprietários e documentação técnica, mitigando alucinações e fornecendo respostas contextualizadas e com fontes verificáveis.

---

## ☁️ Serviços, Tecnologias e Dependências

- **Amazon Bedrock Knowledge Bases:** Serviço gerenciado de ingestão, chunking e recuperação vetorial (região oficial: `us-east-1` — Norte da Virgínia).
- **Modelos de Embeddings:** Amazon Titan Text Embeddings v2 (`amazon.titan-embed-text-v2:0`).
- **Armazenamento de Dados:** Amazon S3 (data source de documentos) integrado a vector store gerenciado (Amazon OpenSearch Serverless ou S3 Vectors).
- **Node.js (ESM):** Node.js >= 18 com `@aws-sdk/client-bedrock-runtime`, `@aws-sdk/client-bedrock-agent-runtime` e `@aws-sdk/credential-providers`.

---

## 📜 Scripts Migrados e Objetivos

> [!NOTE]
> Os scripts de execução utilizados neste laboratório não fazem parte da versão pública deste repositório. A documentação técnica permanece disponível para consulta e estudo.

| Arquivo | Objetivo Técnico |
|---|---|
| `v7-rag-danilo.mjs` | RAG básico com busca vetorial explícita via `RetrieveCommand` (`BedrockAgentRuntimeClient`), filtro de score e injeção manual dos trechos recuperados no payload do `ConverseCommand`. |
| `v7-rag-curado-danilo.mjs` | RAG com curadoria avançada de trechos, descarte de ruído semântico por corte de score mínimo e formatação otimizada para o LLM. |
| `v8-rag-managed-danilo.mjs` | RAG totalmente gerenciado com suporte a reranking e execução combinada com ferramentas locais. |

---

## ⚙️ Variáveis de Ambiente e Configurações

| Variável | Obrigatória | Padrão | Descrição |
|---|:---:|:---:|---|
| `AWS_PROFILE` | Não | `default` | Perfil configurado no `~/.aws/credentials`. |
| `KB_ID` | Sim | `SEU_KB_ID` | Identificador da Knowledge Base no Amazon Bedrock. |
| `SCORE_MINIMO` | Não | `0.4` | Limiar mínimo de relevância semântica para injeção de trecho no contexto. |
| `TOP_K` | Não | `5` | Quantidade máxima de trechos recuperados por busca vetorial. |
| `RERANKING` | Não | `true` (v8) | Habilita reordenação semântica dos trechos recuperados. |
| `LOG` | Não | `false` | Se definido como `true`, grava logs detalhados de prompt e chunks em arquivo. |
| `PROMPT_PATH` | Não | Automático | Caminho customizado para o arquivo de prompt. |
| `PROMPT_FILE` | Não | `prompt-valendo-Danilo.txt` | Nome do prompt carregado a partir de `../shared/prompts/`. |

---

## 💻 Instruções de Execução na VM Ubuntu

```bash
# Navegar até a pasta do desafio
cd ~/formacaoaws/bia-cloud-lab/DESAFIOS/05-IA-bedrock/05-rag-knowledge-base

# Definir as credenciais e o ID da Knowledge Base criada na AWS
export AWS_PROFILE="seu-profile"
export KB_ID="ABC123XYZ4"

# Opcional: ajustar parâmetros de corte de ruído
export SCORE_MINIMO="0.45"
export TOP_K="3"

# Executar a aplicação de RAG
node v7-rag-danilo.mjs
node v8-rag-managed-danilo.mjs
```

### Exemplos de Consultas que Disparam a Busca no KB:
- `"quanto custa o ingresso VIP?"`
- `"quais são as regras de reembolso do curso?"`
- `"o curso gravado tem acesso vitalício?"`

---

## 🌐 Recursos Externos e Infraestrutura AWS

- **Knowledge Base no Amazon Bedrock:** Base de conhecimento configurada e sincronizada na região `us-east-1`.
- **Bucket S3 e Data Source:** Repositório de documentos contendo as fontes de dados em Markdown (ex.: [`knowledge-base/imersao/comparativo-produtos-imersao-formacao.md`](knowledge-base/imersao/comparativo-produtos-imersao-formacao.md)).
- **Vector Store:** Coleção vetorial no Amazon OpenSearch Serverless ou S3 Vectors.
- **Permissões IAM:** `bedrock:Retrieve`, `bedrock:RetrieveAndGenerate` e `bedrock:InvokeModel`.

---

## 📋 Status e Validação de Evidências

- **Estado:** ✅ Concluído.
- **Implementações Realizadas:**
  - Criação e curadoria de base documental em Markdown cobrindo toda a grade técnica da Formação AWS.
  - Implementação de RAG em código Node.js (modo local/curado e modo gerenciado via Bedrock KB).
  - Geração de logs de recuperação e cálculo de métricas de relevância de trechos recuperados.
- **Evidências Registradas:** Scripts funcionais validados no laboratório Colorado (`v7-rag-danilo.mjs`, `v7-rag-curado-danilo.mjs` e `v8-rag-managed-danilo.mjs`) com diagramas de fluxo vetorial.

---

## 🔗 Relação com a Aplicação Core

Base para criação do agente de documentação e busca técnica sobre os módulos e desafios da aplicação BIA.
