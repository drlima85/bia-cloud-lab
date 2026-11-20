# Desafio 03 — Gestão Operacional do ECS via AWS MCP Server

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Infraestrutura AWS & Computação<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Configuração de servidor Model Context Protocol (MCP) para inspeção e diagnóstico seguro do Amazon ECS em modo read-only com política IAM de menor privilégio.<br>
> **Documentação Arquitetural:** [📐 Diagrama & Arquitetura Detalhada](docs/architecture.md) | [🏛️ Decisões da Trilha (ADRs)](../docs/architecture-decisions.md)

---

## 🎯 Objetivo Arquitetural

Integrar a camada de governança, observabilidade e diagnósticos do **Amazon ECS** com agentes de inteligência artificial através de um servidor especializado baseado no **Model Context Protocol (MCP)** (`mcp-proxy-for-aws`).

Essa integração permite que agentes autônomos inspecionem o estado de clusters, identifiquem tarefas ativas, monitorem consumo de recursos e analisem eventos de falha ou reinicialização de contêineres de forma conversacional e estruturada, reduzindo a necessidade de comandos manuais repetitivos na AWS CLI.

---

## ☁️ Recursos AWS Envolvidos

- **Amazon ECS:** Leitura de metadados de clusters, descritores de tarefas, serviços e instâncias de contêiner.
- **Amazon CloudWatch:** Consulta a fluxos de logs de execução e métricas de infraestrutura.
- **AWS IAM:** Perfil de acesso de menor privilégio configurado estritamente com permissões de leitura (*ReadOnly*) para os serviços inspecionados.
- **AWS MCP Proxy Server:** Endpoint oficial ou intermediário de protocolo (`https://aws-mcp.<REGIAO>.api.aws/mcp`) intermediado pelo executor `uvx`.

---

## 🛠️ Pré-requisitos

1. **Python 3.11+** instalado na estação de trabalho ou no host de desenvolvimento.
2. Gerenciador de pacotes ultrarrápido **Astral `uv` / `uvx`** instalado (`curl -LsSf https://astral.sh/uv/install.sh | sh`).
3. Perfil AWS configurado localmente via `aws configure` com políticas de leitura associadas (ex: `AmazonECS_ReadOnlyAccess`, `CloudWatchLogsReadOnlyAccess`).
4. Ambiente de desenvolvimento ou assistente de IA configurado com suporte a MCP (ex: Antigravity CLI, Kiro, Cursor ou Claude Desktop).

---

## 🌐 Variáveis Necessárias

| Variável | Descrição | Exemplo de Valor |
|---|---|---|
| `AWS_PROFILE` | Perfil de credenciais com permissão somente-leitura | `n8n-lab`, `bia-dev-readonly` |
| `AWS_DEFAULT_REGION` | Região padrão para resolução dos comandos do proxy | `us-east-1`, `us-east-2` |
| `AWS_REGION` | Região onde o cluster e os serviços ECS estão ativos | `us-east-2` |

---

## 📄 Templates Fornecidos

Neste desafio, é disponibilizado um modelo sanitizado de configuração MCP:

- [`mcp/mcp-proxy-aws.example.json`](mcp/mcp-proxy-aws.example.json)

> [!WARNING]
> **Substituição Obrigatória de Placeholders antes da Utilização:**
> O arquivo `mcp/mcp-proxy-aws.example.json` utiliza identificadores genéricos como `<REGIAO_DO_MCP_SERVER>`, `<SUA_REGIAO_AWS>` e `<SEU_PERFIL_AWS>`.
> **Esses valores devem ser substituídos pelas configurações locais da sua estação antes de registrar o servidor MCP.** Se a configuração for importada com os placeholders intocados, o comando `uvx` falhará na autenticação ou apontará para um endpoint inexistente.

---

## 📂 Referências Relativas aos Arquivos Existentes

| Arquivo Original | Finalidade e Descrição |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Documento arquitetural dedicado do Desafio 03 contendo diagrama Mermaid do MCP proxy, fluxos de tool calling, controles de menor privilégio e limitações. |
| [`../../../.agents/mcp_config.json`](../../../.agents/mcp_config.json) | Configuração ativa do servidor MCP utilizada no projeto para diagnósticos assistidos por IA no cluster BIA. |
| [`../../../scripts/user_data_ec2_zona_a.sh`](../../../scripts/user_data_ec2_zona_a.sh#L42-L47) | Script de bootstrap da instância EC2 contendo a automação de instalação do Python 3.11 e Astral `uv` para suporte a ferramentas MCP. |

---

## 🚀 Roteiro de Configuração e Uso

### Passo 1: Instalação do Astral uv (caso não esteja instalado)
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.bashrc
```

### Passo 2: Parametrização da Configuração do MCP
Copie o template sanitizado para o diretório de configuração do seu assistente de IA:
```bash
cp mcp/mcp-proxy-aws.example.json mcp-config.json
# Edite o arquivo mcp-config.json substituindo:
# - <REGIAO_DO_MCP_SERVER> pela região do endpoint da AWS (ex: us-east-1)
# - <SUA_REGIAO_AWS> pela região dos seus recursos (ex: us-east-2)
# - <SEU_PERFIL_AWS> pelo nome do perfil local (ex: n8n-lab)
```

### Passo 3: Execução de Diagnósticos Operacionais Assistidos
Com o servidor MCP ativo, o agente de IA é capaz de executar chamadas de ferramentas (*tool calling*) para consultas como:
- *"Qual o estado atual das tasks do serviço service-bia no cluster cluster-bia?"*
- *"Houve alguma falha de inicialização de contêiner nos últimos 15 minutos?"*
- *"Quantas instâncias EC2 estão registradas como Container Instances no cluster?"*

---

## 🛡️ Decisões de Governança e Segurança

1. **Restrição de Privilégios (ReadOnly):** O perfil AWS associado ao MCP Server nunca deve conter políticas administrativas (`AdministratorAccess`) ou de escrita destrutiva (`ec2:Terminate*`, `ecs:Delete*`).
2. **Auditoria de Sessão:** Toda chamada realizada pelo MCP proxy é autenticada com as credenciais do perfil local, gerando trilhas de auditoria no AWS CloudTrail.
3. **Isolamento de Credenciais:** O token ou credencial temporária não é gravado no arquivo de configuração do MCP; apenas o nome do perfil (`AWS_PROFILE`) é referenciado.
