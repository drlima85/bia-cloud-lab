# 🌱 Trilha: AWS Elastic Beanstalk

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** AWS Elastic Beanstalk<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído (Fases D.1, D.2 e D.3)<br>

Estudo prático do modelo Platform-as-a-Service (PaaS) da AWS com **Elastic Beanstalk**, explorando o empacotamento em contêineres Docker, a automação do processo de publicação de versões sem código-fonte pesado, a parametrização de scripts operacionais e o fluxo com a **EB CLI**.

## 📚 Atribuição e Origem

- **Projeto:** BIA Cloud Lab — D2NS
- **Referência educacional:** Formação AWS, conduzida por [Henrylle Maia](https://www.linkedin.com/in/henrylle/).
- **Implementação e adaptações:** Desenvolvidas por **Danilo Lima — D2NS** a partir do repositório de laboratório `bia-eb`, com foco em empacotamento declarativo Docker Compose, injeção dinâmica de tags de commit Git, geração automatizada de pacotes de release em formato `.zip` e parametrização defensiva na Fase D.3.
- **Adaptações D2NS:** Padronização de scripts com validações defensivas de formato (AWS Region e repositório ECR), sanitização de manifestos eliminando senhas em texto claro, auditoria de integridade do pacote ZIP sem remoção destrutiva e guia EB CLI com menor privilégio IAM.
- **Preservação do histórico:** O repositório histórico `bia-eb` permanece preservado de forma independente, enquanto as documentações, diagramas, templates sanitizados e scripts parametrizados são consolidados neste diretório.

---

## 🎯 Índice dos Desafios

| Desafio | Título | Estado | Recursos AWS Principais | Foco Técnico |
|:---:|---|:---:|---|---|
| **01** | [01-eb-docker-deploy](01-eb-docker-deploy/README.md) | ✅ Concluído (D.1, D.2, D.3) | Elastic Beanstalk (Docker), ECR, RDS PostgreSQL, ALB, EB CLI | Empacotamento Docker para Elastic Beanstalk, scripts parametrizados de build/release e guia EB CLI. |

---

## 🛠️ Pré-requisitos Globais da Trilha

1. **Docker Engine** instalado e em execução localmente para compilação da imagem da BIA.
2. **AWS CLI v2** configurado com credenciais válidas e permissões com menor privilégio nos serviços Elastic Beanstalk, ECR, EC2, RDS e CloudWatch.
3. Utilitário **`zip`** disponível no terminal para empacotamento de releases.
4. Repositório **Amazon ECR** criado para armazenar as imagens da aplicação (ex: `bia` ou `bia-cloud-lab`).
5. Banco de dados relacional **Amazon RDS PostgreSQL** provisionado e acessível na VPC.
6. Permissões de IAM:
   - Permissão com menor privilégio para criar e atualizar ambientes Elastic Beanstalk.
   - Instance Profile `aws-elasticbeanstalk-ec2-role` com a política gerenciada `AmazonEC2ContainerRegistryReadOnly` e `AWSElasticBeanstalkWebTier`.
   - Service Role `aws-elasticbeanstalk-service-role` com `AWSElasticBeanstalkEnhancedHealth`.
7. Utilitário opcional **EB CLI (`awsebcli`)** para deploy ágil via linha de comando.

---

## 🌐 Variáveis Globais de Ambiente

| Variável | Descrição | Exemplo de Valor |
|---|---|---|
| `AWS_PROFILE` | Perfil de credenciais ativas da AWS CLI | `bia-dev`, `formacaoaws` |
| `AWS_REGION` | Região onde o Beanstalk e os recursos residem | `us-east-1` |
| `AWS_ACCOUNT_ID` | Identificador de 12 dígitos da conta AWS | `123456789012` |
| `ECR_REPO_NAME` | Nome do repositório no ECR | `bia` |
| `IMAGE_TAG` / `TAG` | Tag de versão da imagem Docker (geralmente commit hash) | `9e6e0e8`, `latest` |
| `DB_HOST` | Endpoint do banco RDS PostgreSQL | `bia.xxxxxx.us-east-1.rds.amazonaws.com` |
| `DB_USER` | Usuário do PostgreSQL | `postgres` |
| `DB_PWD` | Senha de conexão ao banco (injetada de forma segura) | `${DB_PWD}` |
| `DB_PORT` | Porta de conexão do banco | `5432` |

---

## 🗺️ Arquitetura e Engenharia da Solução

A arquitetura completa, o fluxo de build e release, os diagramas detalhados em Mermaid, a comparação entre métodos de deploy e a matriz de evidências estão formalizados no documento:

👉 **Consulte:** [`docs/architecture.md`](docs/architecture.md)

---

## 📂 Papel Histórico dos Arquivos de Laboratório (`bia-eb`)

Os artefatos originais construídos durante os experimentos no repositório de laboratório `bia-eb/bia-eb/` desempenharam as seguintes funções:

- **`Dockerrun.aws.json`:** Manifesto declarativo inicial explorando o modo *Single Container Docker* do Elastic Beanstalk.
- **`compose-eb.yml`:** Definição moderna de serviços em Docker Compose parametrizado com a variável `${TAG}`.
- **`gerar-compose.sh`:** Automação empírica de extração do commit hash via Git e geração do `docker-compose.yml` final de release.
- **`build.sh`:** Pipeline inicial de compilação da imagem Docker, login e push no ECR, geração de compose e compactação do bundle `.zip`.
- **`bia-versao-9e6e0e8.zip`:** Artefato histórico compilado e testado no console do Elastic Beanstalk.

---

## 🛡️ Decisões de Governança e Segurança

1. **Expurgo de Senhas em Arquivos Versionados:** O arquivo histórico `compose-eb.yml` continha senha em texto claro; foram criados templates sanitizados com placeholders `${DB_PASSWORD}` e `${DB_HOST}`.
2. **Separação de Código e Pacote de Deploy:** O pacote de release enviado ao Elastic Beanstalk (`.zip`) não precisa conter o código-fonte da aplicação BIA, mas apenas o manifesto declarativo (`docker-compose.yml`), uma vez que a aplicação já está empacotada no contêiner publicado no ECR.
3. **IAM com Menor Privilégio:** Acesso ao ECR concedido estritamente através da política de leitura `AmazonEC2ContainerRegistryReadOnly` na role de instância do Beanstalk, evitando permissões administrativas genéricas.
4. **Parametrização Segura (Fase D.3):** Scripts parametrizados [`build-and-push-ecr.sh`](01-eb-docker-deploy/scripts/build-and-push-ecr.sh) e [`package-eb-release.sh`](01-eb-docker-deploy/scripts/package-eb-release.sh) criados sem segredos codificados e com proteção defensiva contra vazamento acidental de `.env`.

---

## 📊 Classificação da Trilha

- **Implementado e Documentado:** Templates sanitizados, scripts parametrizados de build e release, bundle zip histórico e guia operacional EB CLI com menor privilégio.
- **Evidenciado Parcialmente:** Testes na nuvem executados durante as aulas da Formação AWS (evidências empíricas de ambiente funcional sem logs em tempo real retidos localmente).
- **Proposto para Evolução Futura:** Integração automatizada da aplicação Node.js com o **AWS Systems Manager (SSM) Parameter Store** via hooks `.platform/` ou extensões `.ebextensions`.
