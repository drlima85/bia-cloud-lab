# Curso: Amazon Bedrock - LAB Danilo (D2NS)

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Reestruturação de scripts CLI e SDK Node.js, organização de checkpoints de streaming, RAG e Guardrails aplicados ao ecossistema D2NS.

Material do curso de **Amazon Bedrock** do **Henrylle Maia**.

Aqui ficam os projetos de exemplo construídos ao longo das aulas que eu realizei voltadas ao meu laboratório, replicando o conhecimento do curso — do primeiro `converse` via CLI até o assistente com RAG, tools e guardrails.

## Onde fica o quê

| Pasta | Conteúdo |
|---|---|
| `scripts/` | os projetos de cada aula, em CLI e em Node |
| `scripts/sdk-node-danilo/` | as versões em Node, de `v4` a `v9` |
| `material-alunos/` | material de apoio em HTML e PDF |
| `docs-rag-v2-danilo/` · `docs-rag-v2/` | documentos usados no Knowledge Base |
| `apoio/` | anotações e material de referência |

## Região Padrão dos Laboratórios

- **Região Oficial da Formação:** `us-east-1` (Norte da Virgínia).
- Os scripts Shell suportam a substituição via variável de ambiente `REGION` (`${REGION:-us-east-1}`).
- A configuração regional desta trilha é independente dos demais laboratórios do BIA Cloud Lab.
