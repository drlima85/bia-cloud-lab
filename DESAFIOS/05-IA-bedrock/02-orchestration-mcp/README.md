# Desafio 02 — Orquestração de Ferramentas via MCP (Model Context Protocol)

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Amazon Bedrock & IA Generativa<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Integração padronizada de servidores Model Context Protocol (MCP) para acesso seguro à documentação e ferramentas operacionais da AWS.

---

## 🎯 Objetivo Arquitetural

Habilitar a orquestração segura e padronizada de ferramentas externas, documentação oficial da AWS e contexto operacional para agentes de IA por meio do protocolo aberto **Model Context Protocol (MCP)**, desacoplando o modelo das APIs e CLI locais.

---

## ☁️ Serviços e Tecnologias

- **Model Context Protocol (MCP):** Especificação padrão para conexão cliente-servidor de contexto de IA.
- **MCP Servers:** `mcp-proxy-for-aws` e `awslabs.aws-documentation-mcp-server`.
- **Amazon Bedrock:** Modelos com suporte a Tool Use e raciocínio fundamentado em dados externos.

---

## 📋 Status e Validação de Evidências

- **Estado:** ✅ Concluído.
- **Implementações Realizadas:** Configuração e homologação de servidores MCP integrados ao ecossistema de agentes, permitindo consultas dinâmicas à documentação oficial AWS e chamadas de inspeção de recursos via proxy de menor privilégio.
- **Evidências Registradas:** Validação da interoperabilidade entre os arquivos de configuração MCP (`mcp_config.json`) e execução das ferramentas pelos agentes em sessões técnicas.

---

## 🔗 Relação com a Aplicação Core

Permite que os agentes de apoio consultem documentação oficial da AWS e inspecionem componentes da infraestrutura BIA sem necessidade de credenciais de administrador embutidas nos prompts.
