# Decisões Arquiteturais (ADRs) — Trilha AWS Infrastructure

> **Localização:** `DESAFIOS/01-aws-infrastructure/docs/architecture-decisions.md`<br>
> **Trilha:** Infraestrutura AWS & Computação<br>
> **Repositório Central:** [`bia-cloud-lab`](../../../)<br>
> **Autores e Referência:** Formação AWS (Henrylle Maia) | Adaptações e Governança: BIA Cloud Lab (Danilo Lima)<br>
> **Data de Atualização:** 2026-11-19<br>
> **Status:** ✅ Documento Normativo e Consolidado<br>

---

## 1. Contexto e Objetivos

Este documento consolida as **Decisões Arquiteturais (*Architecture Decision Records — ADRs*)** tomadas durante o planejamento, provisionamento, evolução e governança da trilha de infraestrutura da aplicação BIA Cloud Lab.

O objetivo do laboratório foi transicionar uma aplicação monolítica moderna (frontend em React 18 / Vite e backend em Node.js 22 LTS / Express) de um modelo de execução tradicional em máquina virtual EC2 única para uma arquitetura profissional de contêineres gerenciados na nuvem AWS, com segregação de redes, aceleração de leitura em memória, injeção segura de parâmetros e governança assistida por inteligência artificial.

As decisões documentadas a seguir fundamentam-se em evidências comprovadas nos scripts operacionais ([`scripts/`](../../../scripts/)), manifestos de infraestrutura ([`templates/`](../02-ecs-alb-rds-cloudmap/templates/)), código de runtime ([`lib/cache.js`](../../../lib/cache.js), [`config/database.js`](../../../config/database.js)) e esteiras de automação ([`deploy-ecs.sh`](../../../deploy-ecs.sh)).

---

## 2. Registro de Decisões Arquiteturais (ADRs)

---

### ADR-01: Escolha do Modelo de Computação — EC2 (Docker Compose) vs ECS (awsvpc)

* **Status:** ✅ **Implementado e Documentado** (Estratégia *Dual-Track* Didática)
* **Contexto:**
  A aplicação BIA precisava suportar tanto um ambiente de validação rápida e baixo custo para desenvolvimento inicial quanto um ambiente orquestrado escalável e aderente às melhores práticas de nuvem.
* **Decisão Tomada:**
  Adotou-se uma estratégia de dois níveis (*dual-track*):
  1. **Nível 1 (Desafio 01 — Implementado e Documentado):** Instância **Amazon EC2** única (`t3.micro`) provisionada via AWS CLI com User Data automatizado ([`scripts/user_data_ec2_zona_a.sh`](../../../scripts/user_data_ec2_zona_a.sh)), utilizando **Docker Compose v2** local para rodar a stack completa (`server`, `database`, `redis`). Serviu como ambiente de transição e homologação rápida.
  2. **Nível 2 (Desafio 02 — Implementado e Documentado):** Orquestração no **Amazon ECS** com launch type **EC2** utilizando o modo de rede **`awsvpc`** ([`task-def.example.json`](../02-ecs-alb-rds-cloudmap/templates/task-def.example.json)). No modo `awsvpc`, cada tarefa ECS recebe sua própria Interface de Rede Elástica (ENI) e um IP privado dedicado dentro da VPC.
* **Justificativa e Evidências:**
  - O modo `awsvpc` no ECS elimina o conflito de portas estáticas no host Docker, permite que regras de Security Group sejam aplicadas diretamente no nível de contêiner e viabiliza a integração direta com Target Groups do Application Load Balancer em modo `ip`.
  - Comprovado nos scripts [`scripts/lancar_ec2_zona_a.sh`](../../../scripts/lancar_ec2_zona_a.sh), [`compose.yml`](../../../compose.yml) e no orquestrador [`deploy-ecs.sh`](../../../deploy-ecs.sh).
* **Consequências:**
  - *Positivas:* Alta flexibilidade de homologação local via Compose e isolamento de rede profissional em nuvem via ECS `awsvpc`.
  - *Negativas / Trade-offs:* Exige gerenciar instâncias de contêiner EC2 (ECS Container Agent) em vez de um modelo puramente serverless como AWS Fargate (escolha feita para manter custos previsíveis no laboratório).

---

### ADR-02: Balanceamento de Carga com ALB e Análise de Service Discovery (AWS Cloud Map)

* **Status:**
  - **Application Load Balancer (ALB):** ✅ **Implementado e Documentado**
  - **AWS Cloud Map:** ⚠️ **Proposto para Evolução Futura (Não Implementado na Prática)**
* **Contexto:**
  A distribuição de tráfego de usuários para os contêineres da aplicação exigia roteamento inteligente com verificações ativas de saúde. Paralelamente, avaliou-se a necessidade de descoberta de serviços (*Service Discovery*) via DNS privado.
* **Decisão Tomada:**
  1. **Adoção do ALB (Implementado e Documentado):** O tráfego externo é centralizado em um **Application Load Balancer** público, com listener HTTP direcionando requisições para um Target Group configurado em modo `ip` na porta 8080. O Target Group executa verificações contínuas de integridade via requisições ativas ao endpoint `GET /api/ping`.
  2. **Análise de AWS Cloud Map (Proposto para Evolução Futura):** O Cloud Map consta na nomenclatura do Desafio 02 e no material didático como padrão recomendado para arquiteturas de microsserviços desacoplados via DNS privado (`.local`). No entanto, **na topologia real da BIA, o Cloud Map não foi configurado nem registrado no ECS**. Como a BIA opera como um monólito modular, o ALB atua como ponto único de entrada e os demais componentes (RDS e ElastiCache) utilizam endpoints de rede dedicados na VPC.
* **Justificativa e Evidências:**
  - O ALB provê desacoplamento entre clientes e contêineres dinâmicos, drenagem graciosa de conexões e suporte nativo a health checks comprovados em [`deploy-ecs.sh`](../../../deploy-ecs.sh) e [`docs/architecture/aws-ecs-diagram.html`](../../../docs/architecture/aws-ecs-diagram.html).
  - A ausência de chamadas `aws servicediscovery` e de blocos `serviceRegistries` no script de deploy confirma que o Cloud Map permaneceu como componente teórico/proposto.
* **Consequências:**
  - *Positivas:* Simplicidade arquitetural, menor sobrecarga de DNS interno e custos operacionais reduzidos para a escala da aplicação.
  - *Negativas / Trade-offs:* Caso a BIA seja fatiada em microsserviços autônomos no futuro, será necessário introduzir o AWS Cloud Map ou VPC Lattice para resolução interna.

---

### ADR-03: Persistência Relacional — Amazon RDS PostgreSQL vs Banco Local em Contêiner

* **Status:**
  - **Banco Local no Compose & Conexão RDS:** ✅ **Implementado e Documentado**
  - **Multi-AZ RDS Standby Síncrono:** ⚠️ **Proposto para Evolução Futura**
* **Contexto:**
  No Desafio 01, o banco PostgreSQL foi executado como um contêiner Docker no mesmo host EC2 da aplicação. Para ambientes de maior escala, o acoplamento do armazenamento ao ciclo de vida da máquina virtual gerava alto risco de indisponibilidade e perda de dados.
* **Decisão Tomada:**
  Desacoplou-se a camada de banco de dados, adotando o **Amazon RDS PostgreSQL** (versão 16, tipo `db.t3.micro`) provisionado em sub-redes privadas de dados sem IP público (`PubliclyAccessible: false`). O contêiner de banco local no `compose.yml` foi mantido estritamente para suporte ao desenvolvimento desconectado da nuvem.
* **Justificativa e Evidências:**
  - O Amazon RDS oferece gerenciamento automatizado de backups, snapshots pontuais (*point-in-time recovery*), patches de segurança do motor e suporte nativo a criptografia com certificados SSL gerenciados pela AWS (evidenciado em [`config/database.js`](../../../config/database.js#L14-L24)).
  - O isolamento em sub-redes privadas de dados garante que a porta 5432 nunca fique exposta na internet pública.
  - A réplica standby Multi-AZ consta no diagrama conceitual [`docs/architecture/aws-ecs-diagram.html`](../../../docs/architecture/aws-ecs-diagram.html), porém na prática utilizou-se instância Single-AZ para contenção de custos de treinamento.
* **Consequências:**
  - *Positivas:* Desacoplamento do ciclo de vida dos contêineres e resiliência de dados corporativa.
  - *Negativas / Trade-offs:* Custo fixo da instância RDS alocada e necessidade de túnel seguro (ou bastion) para acesso administrativo direto da máquina local do operador.

---

### ADR-04: Estratégia de Aceleração com ElastiCache Valkey e Resiliência por Fallback

* **Status:**
  - **Módulo de Resiliência (`lib/cache.js`) & Valkey Local:** ✅ **Implementado e Documentado**
  - **Cluster ElastiCache na Nuvem:** ⚠️ **Evidenciado Parcialmente (Configuração e Endpoints Históricos)**
* **Contexto:**
  Consultas frequentes e repetitivas de leitura (ex: listagem de tarefas) sobrecarregavam o banco relacional RDS. Buscava-se uma camada de cache em memória de altíssimo desempenho com compatibilidade aberta e suporte a criptografia em trânsito.
* **Decisão Tomada:**
  1. Adoção do **Amazon ElastiCache Valkey** (motor 7.2/8.x de código aberto compatível com Redis OSS) provisionado em sub-redes privadas na porta TCP 6379, com criptografia em trânsito (**TLS**) habilitada na nuvem (`CACHE_TLS=true`).
  2. Implementação do padrão **Cache-Aside** no backend Node.js através do módulo [`lib/cache.js`](../../../lib/cache.js) com biblioteca `ioredis`.
  3. **Mecanismo de Fallback Silencioso e Resiliente:** Caso o cluster Valkey fique temporariamente inacessível ou atinja timeout de conexão (`connectTimeout: 3000ms`), o módulo [`lib/cache.js`](../../../lib/cache.js) captura a falha silenciosamente e realiza a consulta diretamente no RDS PostgreSQL, garantindo que o usuário final nunca receba erro 500 por indisponibilidade do cache.
* **Justificativa e Evidências:**
  - O Valkey é uma distribuição de código aberto sustentada pela Linux Foundation, garantindo longevidade sem bloqueio de licença comercial.
  - A arquitetura de software implementada em [`lib/cache.js`](../../../lib/cache.js) e documentada em [`api/routes/cache-config.js`](../../../api/routes/cache-config.js) comprova a execução prática com tratamento gracioso de exceções.
* **Consequências:**
  - *Positivas:* Redução expressiva de latência (respostas em memória < 2ms), desoneração de CPU do RDS e alta disponibilidade garantida pelo fallback.
  - *Negativas / Trade-offs:* Cluster de nó único no laboratório (sem replicação Multi-AZ ativada) e dados temporariamente desatualizados caso o banco relacional seja mutado diretamente fora da API (mitigado por TTL curto de 15 a 60 segundos).

---

### ADR-05: Governança de Acesso Administrativo — AWS Systems Manager (SSM) vs Chaves SSH

* **Status:** ✅ **Implementado e Documentado**
* **Contexto:**
  O acesso administrativo a servidores virtuais tradicionalmente exige geração e distribuição de chaves criptográficas privadas (`.pem`), abertura da porta 22 (SSH) na borda e gerenciamento manual de permissões de usuários no Linux.
* **Decisão Tomada:**
  Eliminou-se completamente o uso de chaves SSH e a liberação de portas administrativas na borda da VPC. O acesso a instâncias EC2 é realizado exclusivamente através do **AWS Systems Manager Session Manager** utilizando o script [`scripts/start-session-bash.sh`](../../../scripts/start-session-bash.sh).
* **Justificativa e Evidências:**
  - As instâncias EC2 recebem a IAM Role `role-acesso-ssm` com a política gerenciada `AmazonSSMManagedInstanceCore`, criada via [`scripts/criar_role_ssm.sh`](../../../scripts/criar_role_ssm.sh) com a Trust Policy [`scripts/ec2_principal.json`](../../../scripts/ec2_principal.json).
  - O agente nativo `amazon-ssm-agent` estabelece conexões de saída via HTTPS (porta 443) com o endpoint do SSM, dispensando qualquer regra de entrada no Security Group.
* **Consequências:**
  - *Positivas:* Zero risco de vazamento de chaves `.pem` no Git, eliminação de ataques de força bruta na porta 22 e auditoria centralizada de sessões no AWS CloudTrail.
  - *Negativas / Trade-offs:* Requer o plugin do Session Manager instalado na estação de trabalho local do operador (`session-manager-plugin`).

---

### ADR-06: Gerenciamento de Parâmetros e Segredos — Injeção Direta vs SSM Parameter Store

* **Status:** ⚠️ **Evidenciado Parcialmente (Modelo Didático) / Implementação Planejada (Proposto para Evolução)**
* **Contexto:**
  No histórico do laboratório BIA, as variáveis de conexão e credenciais de banco e cache (`DB_HOST`, `DB_USER`, `DB_PWD`, `DB_PORT`, `CACHE_ENDPOINT`, `CACHE_PORT`) foram passadas diretamente como variáveis de ambiente planas no manifesto de execução (`task-def-bia-cloud-alb-v2.json`) ou via `.env`/argumentos no Compose. A auditoria das Fases C.4 e C.5 identificou o risco de exposição de credenciais e identificadores confidenciais versionados em repositório local.
* **Decisão Tomada:**
  1. **Ação Imediata de Governança (Implementado e Documentado):** Bloqueio formal do manifesto sensível real `task-def-bia-cloud-alb-v2.json` no `.gitignore` (regra `:81`) e formulação do template sanitizado [`templates/task-def.example.json`](../02-ecs-alb-rds-cloudmap/templates/task-def.example.json) demonstrando o desacoplamento de senhas através da cláusula nativa `secrets` do Amazon ECS.
  2. **Arquitetura Alvo / Implementação Planejada (Proposto para Evolução Futura):** A centralização formal de `DB_HOST`, `DB_USER`, `DB_PWD` e `CACHE_ENDPOINT` no **AWS Systems Manager (SSM) Parameter Store** (com `DB_PWD` armazenado como `SecureString` criptografada via AWS KMS) e resgatada dinamicamente pelo ECS Agent. No repositório local **não existem scripts de provisionamento de parâmetros SSM para a aplicação BIA nem chamadas ativas de `ssm:GetParameters` no manifesto real executado**, caracterizando a migração completa para o Parameter Store como uma **implementação planejada / evolução arquitetural proposta**.
* **Justificativa e Evidências:**
  - Evidência em template: [`templates/task-def.example.json`](../02-ecs-alb-rds-cloudmap/templates/task-def.example.json) modela a sintaxe `secrets: [{ name: "DB_PWD", valueFrom: "arn:aws:ssm:...:parameter/bia/db/password" }]`.
  - Evidência real executada: o manifesto histórico [`task-def-bia-cloud-alb-v2.json`](../../../task-def-bia-cloud-alb-v2.json) utiliza injeção direta de `DB_PWD` em `environment`.
  - Diferente do laboratório N8N (onde scripts e guias IAM em `n8n-lab/` planejaram parâmetros específicos `/n8n/*`), na BIA não há scripts locais criando os parâmetros `/bia/*` no SSM.
* **Consequências:**
  - *Positivas:* Definição clara do padrão DevSecOps sem mascarar o estado real de execução do laboratório.
  - *Negativas / Trade-offs:* A infraestrutura de laboratório permanece funcional com variáveis de ambiente até que os parâmetros sejam formalmente provisionados na nuvem e a task definition seja atualizada com o bloco `secrets`.

---

### ADR-07: Diagnósticos Operacionais e Observabilidade com AWS MCP Server

* **Status:** ✅ **Implementado e Documentado** (Ferramenta de Estação Local com Acesso ReadOnly)
* **Contexto:**
  A auditoria e diagnóstico de saúde do cluster ECS, serviços e logs de tarefas demandavam comandos longos e repetitivos na AWS CLI ou navegação manual pelo console web.
* **Decisão Tomada:**
  Integrou-se um servidor **Model Context Protocol (MCP)** (`mcp-proxy-for-aws@latest`) acionado sob demanda pelo executor **Astral `uvx`**, configurado em [`mcp_config.json`](../../../.agents/mcp_config.json) e documentado no modelo sanitizado [`mcp-proxy-aws.example.json`](../03-ecs-aws-mcp/mcp/mcp-proxy-aws.example.json).
* **Justificativa e Evidências:**
  - Permite que agentes de IA inspecionem em linguagem natural o status de tarefas, diagnósticos de falha de contêiner e registros do CloudWatch Logs `/ecs/task-def-bia-cloud-alb`.
  - A governança de segurança é garantida pela atribuição estrita de perfis IAM com políticas de **somente leitura** (`AmazonECS_ReadOnlyAccess`, `CloudWatchLogsReadOnlyAccess`), prevenindo mutações indesejadas no ambiente.
  - Opera como ferramenta cliente local de diagnóstico, não representando um daemon ou servidor persistente de nuvem.
* **Consequências:**
  - *Positivas:* Resolução acelerada de incidentes, automação de verificações operacionais e redução de fricção no onboarding de novos engenheiros.
  - *Negativas / Trade-offs:* Dependência de conectividade externa com o gateway HTTPS `api.aws` e necessidade do ecossistema Python 3.11 / `uv` na estação do operador.

---

## 3. Matriz Consolidada de Trade-offs: Disponibilidade, Segurança e Custos

A arquitetura do laboratório equilibrou rigor técnico e viabilidade orçamentária para ambiente de treinamento. A tabela abaixo sintetiza os trade-offs assumidos:

| Eixo Arquitetural | Implementação Real no Laboratório | Recomendação para Produção Corporativa | Trade-off Assumido no Lab |
|---|---|---|---|
| **Alta Disponibilidade** | Single-AZ para EC2 e RDS; cluster ECS com 1 a 2 instâncias `t3.micro`. | Multi-AZ para RDS (Standby síncrono); Auto Scaling Group multi-zona com instâncias distribuídas e Target Group multi-AZ. | Economia substancial de custos de instâncias ativas na AWS; risco aceito de indisponibilidade em caso de queda da zona `us-east-1a`. |
| **Segurança e Isolamento** | Subnets privadas para RDS e ElastiCache; modo `awsvpc`; SSM sem porta 22; segredos via variáveis de ambiente com template planejado para SSM `SecureString`. | Inclusão de AWS WAF na frente do ALB; VPC Endpoints (PrivateLink) para SSM, ECR e CloudWatch; rotação automática de segredos via Secrets Manager. | Segurança robusta na camada de rede sem o custo fixo elevado de NAT Gateways duplicados ou VPC Endpoints corporativos. |
| **Custo de Computação** | Instâncias `t3.micro` compartilhadas com Swapfile de 4 GB; desligamento programado via scripts operacionais. | Instâncias dedicadas ou AWS Fargate com reservas de capacidade (*Savings Plans* / *Compute Savings*). | Manutenção do laboratório dentro do Free Tier / baixo consumo financeiro, utilizando Swapfile para viabilizar compilações pesadas de Node.js em máquinas pequenas. |
| **Entrega Contínua** | Script estruturado [`deploy-ecs.sh`](../../../deploy-ecs.sh) com commit hash e rollback manual/automático. | Pipeline totalmente automatizado no AWS CodePipeline com testes canário e Blue/Green deployment via AWS CodeDeploy. | Velocidade de iteração sem dependência de esteiras externas de CI complexas, mantendo o controle total via CLI. |

---

## 4. Tabela de Distinção: Três Níveis de Maturidade Arquitetural

A tabela a seguir categoriza todos os componentes e práticas da trilha em três níveis estritos de evidência:
1. **Implementado e documentado:** Comprovado em código funcional, scripts operacionais ou manifestos ativos no repositório.
2. **Evidenciado parcialmente:** Presente em modelos/templates didáticos ou configurações históricas, sem automação completa de provisionamento no repositório.
3. **Proposto para evolução futura:** Conceito arquitetural ou recomendação corporativa não configurada na topologia real.

| Recurso / Decisão | Nível de Maturidade | Evidência Concreta Local | Escopo e Observações |
|---|:---:|---|---|
| **EC2 com User Data & Docker Compose** | ✅ **Implementado e documentado** | [`scripts/lancar_ec2_zona_a.sh`](../../../scripts/lancar_ec2_zona_a.sh), [`scripts/user_data_ec2_zona_a.sh`](../../../scripts/user_data_ec2_zona_a.sh), [`compose.yml`](../../../compose.yml) | Desafio 01: VM única, Swapfile 4 GB, stack multicontêiner. |
| **ECS Cluster & Tasks em modo `awsvpc`** | ✅ **Implementado e documentado** | [`deploy-ecs.sh`](../../../deploy-ecs.sh), [`task-def-bia-cloud-alb-v2.json`](../../../task-def-bia-cloud-alb-v2.json) | Desafio 02: EC2 Container Instances, ENI dedicada por task. |
| **Application Load Balancer (ALB)** | ✅ **Implementado e documentado** | [`deploy-ecs.sh`](../../../deploy-ecs.sh), [`docs/architecture/aws-ecs-diagram.html`](../../../docs/architecture/aws-ecs-diagram.html) | Desafio 02: Target Group modo `ip`, health check `/api/ping`. |
| **Persistência Relacional em RDS** | ✅ **Implementado e documentado** | [`config/database.js`](../../../config/database.js), [`task-def-bia-cloud-alb-v2.json`](../../../task-def-bia-cloud-alb-v2.json) | Desafio 02: PostgreSQL 16 privado, SSL remoto. |
| **Acesso Administrativo via SSM Session Manager** | ✅ **Implementado e documentado** | [`scripts/criar_role_ssm.sh`](../../../scripts/criar_role_ssm.sh), [`scripts/start-session-bash.sh`](../../../scripts/start-session-bash.sh) | Desafios 01 e 04: Role `role-acesso-ssm`, zero chaves `.pem`, sem porta 22. |
| **Resiliência de Cache (`lib/cache.js`)** | ✅ **Implementado e documentado** | [`lib/cache.js`](../../../lib/cache.js), [`api/routes/cache-config.js`](../../../api/routes/cache-config.js) | Desafio 04: Padrão Cache-Aside com fallback silencioso para RDS. |
| **MCP Server para Diagnósticos ECS** | ✅ **Implementado e documentado** | [`.agents/mcp_config.json`](../../../.agents/mcp_config.json), [`scripts/user_data_ec2_zona_a.sh`](../../../scripts/user_data_ec2_zona_a.sh) | Desafio 03: Executado sob demanda via `uvx` com IAM ReadOnly. |
| **Cluster ElastiCache Valkey na Nuvem** | ⚠️ **Evidenciado parcialmente** | Referenciado em endpoints de variáveis da task definition | Desafio 04: Valkey local no Compose é funcional; cluster cloud foi operado sem scripts de IaC no repo. |
| **Centralização de Segredos via SSM Parameter Store** | ⚠️ **Evidenciado parcialmente / Implementação planejada** | Template [`templates/task-def.example.json`](../02-ecs-alb-rds-cloudmap/templates/task-def.example.json) | Desafios 02 e 04: Modelo demonstrado com `secrets`; manifesto real usava `environment`. Provisionamento via SSM é evolução planejada. |
| **AWS Cloud Map (Service Discovery Privado)** | ⚠️ **Proposto para evolução futura** | Consta no nome da pasta e notas didáticas de IA | Desafio 02: Nenhum namespace ou API Cloud Map ativo nos scripts da BIA. |
| **RDS Multi-AZ com Standby Síncrono** | ⚠️ **Proposto para evolução futura** | Ilustrado em [`aws-ecs-diagram.html`](../../../docs/architecture/aws-ecs-diagram.html) | Desafio 02: Recomendação corporativa; lab utilizou Single-AZ. |
| **Terminação HTTPS com Certificado ACM no ALB** | ⚠️ **Proposto para evolução futura** | Mapeado no planejamento do N8N | Desafio 02: BIA utilizou listener HTTP na porta 8080. |

> 📌 **Nota sobre a Efemeridade dos Recursos em Nuvem:**<br>
> Os recursos catalogados neste documento referem-se à infraestrutura evidenciada nos arquivos locais do laboratório da Formação AWS. Por se tratar de um ambiente educacional e experimental em nuvem, **não se presume que recursos de nuvem (instâncias EC2, clusters ECS, instâncias RDS ou clusters ElastiCache) continuem em execução ativa**. Os scripts de controle financeiro ([`scripts/ligar_bia_local.sh`](../../../scripts/ligar_bia_local.sh) e [`scripts/parar_bia_local.sh`](../../../scripts/parar_bia_local.sh)) e as boas práticas da trilha visam exatamente evitar a permanência desnecessária de recursos alocados na nuvem.
