# Desafio 02 — Amazon ECS com ALB, RDS e Cloud Map

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Infraestrutura AWS & Computação<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Task Definition estruturada com modo de rede awsvpc, desacoplamento de banco de dados para Amazon RDS PostgreSQL e integração com Application Load Balancer.<br>
> **Documentação Arquitetural:** [📐 Diagrama & Arquitetura Detalhada](docs/architecture.md) | [🏛️ Decisões da Trilha (ADRs)](../docs/architecture-decisions.md)

---

## 🎯 Objetivo Arquitetural

Evoluir a infraestrutura da aplicação BIA para uma arquitetura profissional e orquestrada de contêineres no **Amazon ECS** utilizando o launch type **EC2** com modo de rede **`awsvpc`**, distribuindo o tráfego de entrada através de um **Application Load Balancer (ALB)** com verificações ativas de integridade (*health checks*), persistindo dados no banco relacional gerenciado **Amazon RDS PostgreSQL** e gerenciando imagens privadas de contêiner no **Amazon ECR** com pipeline de deploy e capacidade nativa de *rollback*.

É o ambiente primário de implantação da aplicação BIA Cloud Lab, hospedando o frontend compilado em Vite e a API REST em Node.js 22.

---

## ☁️ Recursos AWS Envolvidos

- **Amazon ECS:** Cluster ECS, Services gerenciados e Task Definitions configuradas em modo de rede `awsvpc` e alocação de CPU/Memória por contêiner.
- **Application Load Balancer (ALB):** Listeners HTTP (porta 80/8080), Target Groups configurados com *health check path* apontando para `/api/ping`.
- **Amazon RDS PostgreSQL:** Instância gerenciada em sub-redes privadas de dados, com Security Groups autorizando acesso exclusivamente originado dos contêineres da aplicação.
- **Amazon ECR (Elastic Container Registry):** Repositório privado de imagens com versionamento semântico e rastreabilidade por *commit hash* Git.
- **AWS CodeBuild / CI-CD:** Automação de compilação, geração de artefatos e entrega contínua.
- **Amazon CloudWatch Logs:** Grupo de logs centralizado (`/ecs/task-def-bia-cloud-alb`) para diagnóstico de runtime.
- **AWS IAM:** `ecsTaskExecutionRole` para puxar imagens do ECR e gravar logs no CloudWatch.

---

## 🛠️ Pré-requisitos

1. **Docker Engine** instalado e em execução na máquina de build (`docker info`).
2. **AWS CLI v2** configurado com credenciais válidas e permissões nos serviços ECS, ECR, EC2, RDS e CloudWatch.
3. Repositório ECR criado na AWS (ex: `bia` ou `bia-cloud-lab`).
4. Cluster ECS criado e associado a instâncias EC2 com o ECS Container Agent ativo.
5. Banco de dados Amazon RDS PostgreSQL provisionado em sub-redes alcançáveis pela VPC da aplicação.

---

## 🌐 Variáveis Necessárias

| Variável | Descrição | Exemplo de Valor |
|---|---|---|
| `AWS_PROFILE` | Perfil de credenciais ativas da AWS CLI | `bia-dev`, `default` |
| `AWS_REGION` | Região onde a infraestrutura ECS/RDS está alocada | `us-east-1`, `us-east-2` |
| `AWS_ACCOUNT_ID` | Identificador de 12 dígitos da conta AWS | `123456789012` |
| `ECR_REGISTRY` | URI base do registro ECR | `<CONTA>.dkr.ecr.<REGIAO>.amazonaws.com` |
| `CLUSTER_NAME` | Nome do cluster ECS | `cluster-bia` |
| `SERVICE_NAME` | Nome do serviço gerenciado no ECS | `service-bia` |
| `DB_HOST` | Endpoint de conexão do banco RDS | `bia-cloud.xxxxxx.us-east-2.rds.amazonaws.com` |
| `DB_PORT` | Porta do PostgreSQL | `5432` |
| `DB_USER` | Usuário do banco de dados | `postgres` |
| `DB_PWD` | Senha do banco (gerenciada via SSM ou env) | `${DB_PASSWORD}` |

---

## 📄 Templates Fornecidos

Neste desafio, é disponibilizado um modelo sanitizado de manifesto de implantação:

- [`templates/task-def.example.json`](templates/task-def.example.json)

> [!WARNING]
> **Substituição Obrigatória de Placeholders antes da Utilização:**
> O arquivo `templates/task-def.example.json` é um **modelo didático sanitizado** e utiliza identificadores fictícios como `<SUA_CONTA_AWS>`, `<SUA_REGIAO_AWS>`, `<SEU_ENDPOINT_RDS_POSTGRES>` e `<SEU_ENDPOINT_ELASTICACHE_VALKEY>`.
> **Ele NÃO é um manifesto pronto para deploy imediato.** Tentar registrar esse JSON sem preencher os valores reais provocará erro de validação na AWS CLI.
> O arquivo sensível de execução real (`task-def-bia-cloud-alb-v2.json`) presente na raiz do repositório contém credenciais de laboratório e **nunca** deve ser versionado publicamente.

---

## 📂 Referências Relativas aos Arquivos Existentes

Os arquivos e scripts operacionais originais permanecem em seus locais de origem na arquitetura da BIA:

| Arquivo Original | Finalidade e Descrição |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Documento arquitetural dedicado do Desafio 02 contendo diagrama Mermaid renderizável, distinção entre componentes comprovados vs propostos (Cloud Map), fluxos de deploy/rollback e controles de segurança. |
| [`../../../deploy-ecs.sh`](../../../deploy-ecs.sh) | Script estruturado de orquestração de deploy para o ECS: automatiza build Docker, push no ECR com tag de commit hash, criação de nova task definition e atualização de serviço, com suporte a `rollback` e `list-versions`. |
| [`../../../scripts/ecs/unix/build.sh`](../../../scripts/ecs/unix/build.sh) | Rotina simplificada Shell para login no ECR, compilação da imagem Docker e push. |
| [`../../../scripts/ecs/unix/deploy.sh`](../../../scripts/ecs/unix/deploy.sh) | Rotina Shell simplificada para acionar nova implantação no cluster ECS (`--force-new-deployment`). |
| [`../../../scripts/ecs/unix/check-disponibilidade.sh`](../../../scripts/ecs/unix/check-disponibilidade.sh) | Script que executa contêiner leve Alpine com monitoramento contínuo de status HTTP da aplicação. |
| [`../../../scripts/ecs/unix/testar-latencia.sh`](../../../scripts/ecs/unix/testar-latencia.sh) | Probe contínuo de latência HTTP e auditoria de cabeçalhos CloudFront/CDN (`X-Cache`, `Cache-Control`). |
| [`../../../scripts/ecs/windows/build.bat`](../../../scripts/ecs/windows/build.bat) | Script Batch para Windows com fluxo de build e push ECR. |
| [`../../../scripts/ecs/windows/deploy.bat`](../../../scripts/ecs/windows/deploy.bat) | Script Batch para Windows com fluxo de deploy forçado no ECS. |
| [`../../../Dockerfile`](../../../Dockerfile) | Definição Docker multi-stage da aplicação BIA (Node.js 22-slim, build do front Vite e runtime backend). |
| [`../../../buildspec.yml`](../../../buildspec.yml) | Manifesto de pipeline para o AWS CodeBuild integrado ao ECR e ECS. |
| [`../../../config/database.js`](../../../config/database.js) | Módulo Sequelize de conexão com o banco RDS com suporte nativo a SSL remoto e AWS Secrets Manager. |
| [`../../../database/migrations/`](../../../database/migrations/) | Scripts de migração relacional do banco de dados PostgreSQL. |
| [`../../../docs/architecture/aws-ecs-diagram.html`](../../../docs/architecture/aws-ecs-diagram.html) | Diagrama interativo de arquitetura com detalhes de rede, ALB, ECS e banco de dados. |

---

## 🚀 Roteiro de Execução Operacional

### Passo 1: Preparação do Manifesto da Task Definition
Copie o template sanitizado para um arquivo de trabalho local (ignorado pelo Git) e substitua os placeholders:
```bash
cp templates/task-def.example.json task-def.json
# Substitua <SUA_CONTA_AWS>, <SUA_REGIAO_AWS>, endpoints e secrets no task-def.json
```

### Passo 2: Registro da Task Definition no ECS
```bash
aws ecs register-task-definition \
  --cli-input-json file://task-def.json \
  --region "${AWS_REGION:-us-east-1}"
```

### Passo 3: Build, Tag e Push da Imagem para o ECR
Utilizando o script orquestrador central:
```bash
cd ../../..
./deploy-ecs.sh deploy -r "${AWS_REGION:-us-east-1}" -e bia-cloud-lab -c cluster-bia -s service-bia
```

### Passo 4: Procedimento de Rollback em Caso de Falha
Caso uma nova versão apresente anomalias no health check do ALB:
```bash
# 1. Listar versões registradas no repositório ECR
./deploy-ecs.sh list-versions -e bia-cloud-lab

# 2. Reverter o serviço imediatamente para o commit hash estável anterior
./deploy-ecs.sh rollback -t <COMMIT_HASH_ANTERIOR> -c cluster-bia -s service-bia
```

---

## 🛡️ Boas Práticas e Resiliência

1. **Health Checks no Target Group:** Configurar o endpoint `/api/ping` com tolerância de 2 falhas consecutivas para desregistrar instâncias não saudáveis do ALB.
2. **Isolamento de Banco de Dados:** O Amazon RDS nunca deve ter acesso público habilitado (`PubliclyAccessible: false`); apenas instâncias autorizadas pelo Security Group do ECS devem se comunicar na porta 5432.
3. **Imagens Base Seguras:** A imagem Docker utiliza a distribuição oficial mínima `public.ecr.aws/docker/library/node:22-slim`, reduzindo a superfície de ataque.
