# 🗺️ Central de Desafios Técnicos — BIA Cloud Lab

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** Consolidação e auditoria das 5 trilhas técnicas<br>

Este diretório reúne e documenta os desafios de engenharia de nuvem, automação, IA generativa e DevOps desenvolvidos ao longo da jornada de capacitação técnica na AWS, adaptados e padronizados para o ecossistema **D2NS**.

## 📚 Créditos e Projetos-Base

- **Projeto:** BIA Cloud Lab — D2NS
- **Programa de Referência:** Formação AWS, conduzida por [Henrylle Maia](https://www.linkedin.com/in/henrylle/).
- **Projetos-Base Educacionais:** Aplicação BIA ([henrylle/bia](https://github.com/henrylle/bia)) e repositório de IA Colorado ([henrylle/colorado](https://github.com/henrylle/colorado)).
- **Implementações e Adaptações D2NS:** Desenvolvidas por **Danilo Lima — D2NS**, com foco em personalização de componentes, modernização de runtime (Node.js 22), governança IAM com menor privilégio, integrações via MCP, parametrização defensiva de scripts operacionais, higienização total de credenciais e consolidação de memoriais arquiteturais com ADRs formais.
- **Licenças e Direitos:** As estruturas conceituais de ensino pertencem aos seus respectivos autores, sendo preservadas todas as atribuições originais.

---

## 🧭 Trilhas de Laboratório

| Trilha | Foco Tecnológico | Desafios Totais |
|---|---|:---:|
| [🏗️ Infraestrutura AWS & Computação](01-aws-infrastructure/README.md) | EC2, ECS, ALB, RDS, Valkey, SSM e MCP | 4 |
| [🌱 AWS Elastic Beanstalk](02-elastic-beanstalk/README.md) | PaaS, empacotamento Docker e ciclo de vida | 1 |
| [⚡ Plataforma de Automação N8N](03-bia-cloud-n8n/README.md) | Single-Mode e Queue Mode desacoplado na AWS | 2 |
| [🔄 Estratégias de Deploy & Resiliência](04-deploy-strategies/README.md) | Rolling Update, Rollback, Blue/Green e IA | 4 |
| [🧠 Amazon Bedrock & IA Generativa](05-IA-bedrock/README.md) | LLMs, Multi-Agentic, MCP, RAG e Guardrails | 6 |

---

## 📋 Critérios de Validação e Evidência

Cada desafio segue uma classificação transparente de maturidade técnica:

- ✅ **Concluído:** implementação concluída e validada em ambiente de laboratório.
- 🔍 **Validação de Evidência:** artefatos e scripts construídos; coleta de evidências de execução ativa na AWS em andamento.
- 🟡 **Pendente na plataforma:** experiência técnica prática já realizada manualmente em laboratórios anteriores, pendente de formalização neste repositório.
- ⚪ **Pendente:** arquitetura planejada para implementação futura.
