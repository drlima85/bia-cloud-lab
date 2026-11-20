# Desafio 01 — Implantação no AWS Elastic Beanstalk

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** AWS Elastic Beanstalk<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** 🔍 Validação de Evidência & Parametrização Concluída (Fases D.1, D.2 e D.3)<br>
> **Adaptações D2NS:** Empacotamento Docker Compose declarativo, injeção dinâmica de commit hash Git em runtime, scripts parametrizados defensivos (`build-and-push-ecr.sh`, `package-eb-release.sh`) e guia EB CLI com menor privilégio IAM.

---

## 🎯 Objetivo Arquitetural

Simplificar o ciclo de vida e a gestão da aplicação web através do **AWS Elastic Beanstalk**, utilizando o provisionamento totalmente gerenciado de recursos (instâncias EC2, load balancers e grupos de auto scaling) e executando a aplicação BIA via contêineres Docker pré-construídos e versionados no **Amazon ECR**.

Este desafio fornece uma estratégia alternativa de implantação para a aplicação BIA, permitindo comparar a complexidade operacional entre o modelo **PaaS gerenciado (Elastic Beanstalk)** e a **orquestração nativa de contêineres (Amazon ECS)** abordada na trilha de infraestrutura.

---

## ☁️ Recursos AWS Envolvidos

- **AWS Elastic Beanstalk:** Ambiente de execução configurado para a plataforma Docker (Amazon Linux 2023).
- **Application Load Balancer (ALB):** Balanceador de carga gerenciado automaticamente pela plataforma Beanstalk com verificação de saúde em `/api/ping`.
- **Auto Scaling Group (ASG):** Dimensionamento elástico automático de instâncias EC2 baseado em métricas de utilização de CPU ou requisições.
- **Amazon ECR:** Armazenamento seguro de imagens Docker versionadas com base na hash curta do commit Git.
- **Amazon RDS PostgreSQL:** Banco de dados relacional que atende às operações da BIA.
- **Amazon CloudWatch:** Coleta automática de logs do daemon Docker e do motor Beanstalk (`/var/log/eb-engine.log`).
- **AWS IAM:** Instance Profile `aws-elasticbeanstalk-ec2-role` com políticas de menor privilégio.

---

## 🛠️ Pré-requisitos

1. **Docker Engine** ativo para compilação da imagem da BIA (`docker info`).
2. **AWS CLI v2** configurado com credenciais válidas e permissões no IAM.
3. Utilitário **`zip`** instalado para geração do pacote de entrega.
4. Repositório **Amazon ECR** criado para armazenar as imagens da aplicação (ex: `bia`).
5. Banco de dados **Amazon RDS PostgreSQL** provisionado e acessível na VPC.
6. Utilitário opcional **EB CLI (`awsebcli`)** para deploy ágil via terminal.

---

## 🌐 Variáveis Necessárias

| Variável | Descrição | Exemplo de Valor |
|---|---|---|
| `AWS_PROFILE` | Perfil de credenciais ativas da AWS CLI | `bia-dev`, `formacaoaws` |
| `AWS_REGION` | Região AWS do ambiente | `us-east-1` |
| `AWS_ACCOUNT_ID` | Identificador de 12 dígitos da conta AWS | `123456789012` |
| `ECR_REPO_NAME` | Nome do repositório no Amazon ECR | `bia` |
| `IMAGE_TAG` / `TAG` | Tag de versão da imagem Docker (hash Git curta) | `9e6e0e8`, `latest` |
| `DB_HOST` | Endpoint de conexão do banco RDS | `bia.xxxxxx.us-east-1.rds.amazonaws.com` |
| `DB_USER` | Usuário do PostgreSQL | `postgres` |
| `DB_PWD` | Senha do banco (gerenciada via variáveis de ambiente) | `${DB_PWD}` |
| `DB_PORT` | Porta de conexão do banco | `5432` |

---

## 📄 Templates Fornecidos

Neste desafio, são disponibilizados dois modelos sanitizados de manifesto de implantação:

1. **Manifesto Docker Compose (Recomendado):**
   - [`templates/compose-eb.example.yml`](templates/compose-eb.example.yml) — Define o serviço `server`, mapeamento da porta `80:8080`, imagem no ECR com tag dinâmica e variáveis de banco.
2. **Manifesto Dockerrun v1 (Legado):**
   - [`templates/Dockerrun.aws.example.json`](templates/Dockerrun.aws.example.json) — Formato Single-Container Docker clássico da AWS.

> [!WARNING]
> **Substituição Obrigatória de Placeholders antes da Utilização:**
> Os arquivos em `templates/` utilizam identificadores genéricos como `<SUA_CONTA_AWS>`, `<SUA_REGIAO_AWS>`, `<SEU_ENDPOINT_RDS_POSTGRES>` e `${DB_PASSWORD}`.
> **Eles NÃO são manifestos prontos para deploy direto.** Todos os placeholders devem ser substituídos pelas configurações reais do ambiente antes de compactar o arquivo de release.

---

## 📂 Scripts Operacionais Parametrizados (Fase D.3)

Para substituir as rotinas manuais com valores hardcoded do laboratório histórico, foram desenvolvidos scripts padronizados e seguros:

| Script | Finalidade e Características |
|---|---|
| [`scripts/build-and-push-ecr.sh`](scripts/build-and-push-ecr.sh) | Executa o build da imagem Docker multi-stage da BIA, autentica no ECR via token temporário e realiza o push com tag baseada no Git commit hash. Totalmente parametrizado (`AWS_REGION`, `AWS_ACCOUNT_ID`, `ECR_REPO_NAME`, `IMAGE_TAG`, `AWS_PROFILE`), com validação defensiva (`set -euo pipefail`). |
| [`scripts/package-eb-release.sh`](scripts/package-eb-release.sh) | Gera o bundle de deploy `.zip` sanitizado contendo exclusivamente o `docker-compose.yml`. Não embute senhas em texto claro, **não copia nem remove arquivos `.env`**, possui proteção contra sobrescrita de ZIPs existentes e auditoria profunda garantindo a preservação literal das referências `${DB_*}` para injeção em runtime. |

---

## 📂 Referências Relativas aos Arquivos Existentes

| Arquivo / Recurso | Finalidade e Descrição |
|---|---|
| [`../docs/architecture.md`](../docs/architecture.md) | Documentação arquitetural profunda da trilha com diagramas Mermaid, topologia de rede, comparativo de esteiras e matriz de evidências. |
| [`../../../Dockerfile`](../../../Dockerfile) | Definição Docker multi-stage da aplicação BIA (Node.js 22 LTS) utilizada para gerar a imagem publicada no ECR. |
| [`../../../compose.yml`](../../../compose.yml) | Definição Docker Compose multicontêiner local para validação prévia de desenvolvimento. |
| `repositório local bia-eb/bia-eb/` | Repositório histórico original contendo os artefatos de laboratório (`gerar-compose.sh`, `build.sh`, `Dockerrun.aws.json`, `compose-eb.yml` e o bundle `bia-versao-9e6e0e8.zip`). **Preservado e inalterado.** |

---

## 🚀 Roteiro de Execução: Método A (Scripts Parametrizados & Console/CLI)

Este método automatiza as etapas locais de compilação, envio para o ECR e geração do bundle sem expor credenciais:

### Passo 1: Compilação e Envio da Imagem para o ECR
Executar o script parametrizado a partir da pasta de scripts ou exportando as variáveis desejadas:
```bash
# Execução parametrizada
AWS_REGION="us-east-1" \
AWS_PROFILE="formacaoaws" \
ECR_REPO_NAME="bia" \
./scripts/build-and-push-ecr.sh
```

### Passo 2: Geração do Bundle ZIP Sanitizado
Gerar o pacote de entrega contendo apenas a especificação declarativa do contêiner:
```bash
AWS_REGION="us-east-1" \
AWS_PROFILE="formacaoaws" \
ECR_REPO_NAME="bia" \
OUTPUT_DIR="./dist" \
./scripts/package-eb-release.sh
```
*O artefato gerado será `dist/bia-versao-<TAG>.zip`, pesando menos de 2 KB.*

### Passo 3: Configuração de Variáveis no Elastic Beanstalk
No Console Web do Elastic Beanstalk (*Configuration > Updates, monitoring, and logging > Environment properties*) ou via CLI gerenciado, configurar as variáveis da aplicação:
- `DB_HOST`: endpoint privado do RDS PostgreSQL.
- `DB_USER`: `postgres`
- `DB_PWD`: senha de acesso ao banco (armazenada de forma protegida).
- `DB_PORT`: `5432`

### Passo 4: Implantação da Versão
Realizar o upload do arquivo `dist/bia-versao-<TAG>.zip` no console (*Application versions > Upload and deploy*) ou via AWS CLI:
```bash
aws elasticbeanstalk create-application-version \
  --application-name "bia-app" \
  --version-label "<TAG>" \
  --source-bundle S3Bucket="<SEU_BUCKET_EB>",S3Key="bia-versao-<TAG>.zip"

aws elasticbeanstalk update-environment \
  --environment-name "bia-env" \
  --version-label "<TAG>"
```

---

## 💻 Roteiro de Execução: Método B (AWS Elastic Beanstalk CLI — `awsebcli`)

A **EB CLI** é a interface de linha de comando oficial da AWS otimizada para o Elastic Beanstalk, permitindo gerenciar ambientes, deploys e diagnósticos diretamente pelo terminal.

> [!NOTE]
> Os comandos a seguir são apresentados como **exemplos documentais**. Nenhuma ação de criação de recursos na AWS é executada automaticamente.

### 1. Instalação e Configuração da EB CLI
A EB CLI pode ser instalada via gerenciador Python `pip`:
```bash
pip install awsebcli --upgrade --user
eb --version
```

### 2. Governança IAM e Princípio do Menor Privilégio
Não se deve utilizar políticas irrestritas (como `AdministratorAccess` ou `AWSElasticBeanstalkFullAccess` irrestrita). Recomenda-se a separação estrita por entidade:

1. **Instance Profile da EC2 (`aws-elasticbeanstalk-ec2-role`):**
   - Política `AmazonEC2ContainerRegistryReadOnly`: autoriza o download das imagens privadas da BIA a partir do ECR.
   - Política `AWSElasticBeanstalkWebTier`: concede permissões para comunicação com o subsistema do Beanstalk e upload de logs de saúde para o CloudWatch.
2. **Service Role do Elastic Beanstalk (`aws-elasticbeanstalk-service-role`):**
   - Política `AWSElasticBeanstalkEnhancedHealth`: permite ao control plane coletar métricas avançadas do cluster e ALB.
   - Política `AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy`: autoriza atualizações gerenciadas de plataforma.
3. **Credencial do Operador / CI/CD:**
   - Permissões limitadas aos namespaces `elasticbeanstalk:*`, `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `s3:GetObject`/`s3:PutObject` no bucket de releases do Beanstalk, e `iam:PassRole` restrita às roles mencionadas acima.

### 3. Inicialização do Projeto (`eb init`)
Vincular o repositório local a uma aplicação Elastic Beanstalk:
```bash
eb init bia-app \
  --platform "Docker running on 64bit Amazon Linux 2023" \
  --region "us-east-1" \
  --profile "formacaoaws"
```
*O utilitário cria o diretório de metadados `.elasticbeanstalk/` na raiz do projeto.*

### 4. Criação do Ambiente Gerenciado (`eb create`)
Criar o ambiente PaaS provisionando automaticamente o ALB, o Auto Scaling Group e associando o Instance Profile seguro:
```bash
eb create bia-prod-env \
  --instance-profile "aws-elasticbeanstalk-ec2-role" \
  --elb-type application \
  --cname "bia-app-prod"
```

### 5. Gestão Segura de Variáveis de Ambiente
> [!CAUTION]
> **Risco de Exposição de Senhas na Linha de Comando:**<br>
> Evite executar `eb setenv DB_PWD=minhasenha` diretamente no terminal, pois parâmetros passados via flag de shell são gravados em texto claro no histórico (`~/.bash_history`), na tabela de processos do sistema operacional (`ps aux`) e em logs locais.

**Alternativas Seguras Recomendadas:**
1. **Configuração Interativa no Console Web:** Inserir a senha diretamente no painel criptografado de *Environment Properties*.
2. **Arquivo de Configuração Protegido:** Utilizar um arquivo `.ebextensions/options.config` ou script temporário com permissões `chmod 600` e variáveis transitórias, garantindo que seja ignorado pelo Git (`.gitignore`).
3. **Integração com AWS SSM Parameter Store (*Proposta para Evolução Futura*):**
   - Configurar a aplicação ou script de inicialização (`.platform/hooks/predeploy/`) para consultar parâmetros do tipo `SecureString` em `/bia/prod/db_password` via AWS SDK ou AWS CLI, utilizando a IAM Role da instância para autenticação sem senhas em arquivos de configuração. *(Nota: Não implementado na versão atual; catalogado como proposta).*

### 6. Implantação Contínua (`eb deploy`)
Após gerar o bundle ou apontar para a versão do manifesto:
```bash
eb deploy bia-prod-env
```

### 7. Diagnósticos, Observabilidade e Encerramento
Comandos úteis para o ciclo de vida do ambiente:
```bash
# Verificar status geral e CNAME ativo
eb status

# Monitorar a saúde detalhada das instâncias e latência do ALB
eb health

# Obter as últimas 100 linhas de log da plataforma e contêineres Docker
eb logs --tail

# Acessar a aplicação no navegador
eb open

# Encerrar e desalocar todos os recursos AWS do ambiente (desprovisionamento seguro)
eb terminate bia-prod-env
```

---

## 🛡️ Matriz de Maturidade e Classificação de Estado

| Componente / Recurso | Classificação de Estado | Detalhes da Implementação |
|---|:---:|---|
| **Scripts Parametrizados de Build/Release** | ✅ Implementado e Documentado | [`scripts/build-and-push-ecr.sh`](scripts/build-and-push-ecr.sh) e [`scripts/package-eb-release.sh`](scripts/package-eb-release.sh) criados com parametrização dinâmica, `set -euo pipefail` e sem segredos gravados. |
| **Manifesto Docker Compose Sanitizado** | ✅ Implementado e Documentado | [`templates/compose-eb.example.yml`](templates/compose-eb.example.yml) com injeção dinâmica de variáveis de ambiente. |
| **Bundle ZIP Histórico de Release** | ✅ Implementado e Documentado | Pacote binário `bia-versao-9e6e0e8.zip` preservado em `bia-eb/bia-eb/`. |
| **Guia Operacional EB CLI (`awsebcli`)** | ✅ Implementado e Documentado | Fluxo completo documentado com princípios de menor privilégio e segurança de senhas. |
| **Validação de Logs Ativos na Nuvem** | 🔍 Evidenciado Parcialmente | Testes operacionais executados na nuvem durante a formação; logs de execução não persistidos localmente. |
| **Injeção de Segredos via SSM Parameter Store** | ⚪ Proposto para Evolução Futura | Mapeado arquiteturalmente; requer implementação de hook ou suporte nativo no código Node.js. |
