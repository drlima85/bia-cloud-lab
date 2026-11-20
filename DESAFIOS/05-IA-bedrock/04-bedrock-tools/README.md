# Desafio 04 — Chamada de Ferramentas (Tool Use / Function Calling)

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Definição defensiva de schemas JSON de ferramentas, tratamento de erros no consumo de parâmetros retornados pelo modelo e integração com APIs de negócio da BIA.

---

## 🎯 Objetivo Arquitetural

Capacitar o modelo de linguagem a reconhecer quando uma pergunta do usuário exige dados do mundo real ou computação específica, delegando a execução para funções locais (*Tool Use*) via schemas padronizados e processando o resultado retornado.

---

## ☁️ Serviços, Tecnologias e Dependências

- **Amazon Bedrock:** API Converse com suporte a especificação de `toolConfig` (região oficial: `us-east-1` — Norte da Virgínia).
- **Node.js (ESM):** Node.js >= 18 com `@aws-sdk/client-bedrock-runtime` e `@aws-sdk/credential-providers`.
- **Validação de Schemas:** Definição de contratos JSON Schema para argumentos de entrada das ferramentas (`consultar_matricula` e `gerar_link_pagamento`).

---

## 📜 Scripts Migrados e Objetivos

> [!NOTE]
> Os scripts de execução utilizados neste laboratório não fazem parte da versão pública deste repositório. A documentação técnica permanece disponível para consulta e estudo.

| Arquivo | Objetivo Técnico |
|---|---|
| `v6-primeira-tool-danilo.mjs` | Implementação de Tool Use / Function Calling no Bedrock. Intercepta requisições de execução de ferramentas locais (`toolUse`), processa consultas de negócio e devolve o `toolResult` ao LLM para formulação da resposta final. |

---

## ⚙️ Variáveis de Ambiente e Configurações

| Variável | Obrigatória | Padrão | Descrição |
|---|:---:|:---:|---|
| `AWS_PROFILE` | Não | `default` | Perfil configurado no `~/.aws/credentials`. |
| `REGION` | Não | `us-east-1` | Região AWS do Amazon Bedrock. |
| `PROMPT_PATH` | Não | Automático | Caminho customizado para o arquivo de prompt. |
| `PROMPT_FILE` | Não | `prompt-valendo-Danilo.txt` | Nome do prompt carregado a partir de `../shared/prompts/`. |

---

## 💻 Instruções de Execução na VM Ubuntu

```bash
# Navegar até a pasta do desafio
cd ~/formacaoaws/bia-cloud-lab/DESAFIOS/05-IA-bedrock/04-bedrock-tools

# Definir o perfil AWS de execução
export AWS_PROFILE="seu-profile"

# Executar a aplicação de tools
node v6-primeira-tool-danilo.mjs
```

### Exemplos de Mensagens de Teste (Interação Interativa):
- **Consulta de status:** `"minha compra saiu? meu email é maria@email.com"`
- **Verificação de duplicidade:** `"quero pagar o VIP, vou assistir ao vivo, meu email é maria@email.com"`
- **Geração de novo link:** `"quero pagar o Normal, meu email é joao@email.com"`

---

## 🌐 Recursos Externos e Integrações

- **Amazon Bedrock Model Access:** Modelo Claude 3.5 Sonnet habilitado em `us-east-1`.
- **Mocks Locais de Negócio:** Base em memória simulando tabelas relacionais de alunos e pedidos para resolução das chamadas de ferramentas.
- **Permissões IAM:** `bedrock:InvokeModel` associado ao perfil ativo.

---

## 📋 Status e Validação de Evidências

- **Estado:** ✅ Concluído.
- **Implementações Realizadas:** Script em Node.js com definição de ferramenta personalizada (ex.: consulta de dados e regras de negócio), interceptação de `toolUse` retornado pelo Bedrock, execução do código local e envio do `toolResult` de volta ao modelo para composição da resposta final.
- **Evidências Registradas:** Execução validada no laboratório Colorado (`scripts/sdk-node-danilo/v6-primeira-tool-danilo.mjs`).

---

## 🔗 Relação com a Aplicação Core

Permite que a IA execute operações programáticas, como consultar a versão atual da API BIA, listar tarefas pendentes ou disparar rotinas administrativas autorizadas.
