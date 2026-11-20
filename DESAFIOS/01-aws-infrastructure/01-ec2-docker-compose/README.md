# Desafio 01 — Provisionamento EC2 e Docker Compose

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Infraestrutura AWS & Computação<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído<br>
> **Adaptações D2NS:** Automação de User Data com suporte idempotente, IAM Role SSM dedicada e modernização do ambiente Docker Compose v2.<br>
> **Documentação Arquitetural:** [📐 Diagrama & Arquitetura Detalhada](docs/architecture.md) | [🏛️ Decisões da Trilha (ADRs)](../docs/architecture-decisions.md)

---

## 🎯 Objetivo Arquitetural

Automatizar o provisionamento de instâncias Amazon EC2 utilizando scripts de inicialização (*User Data*), preparando o host com Docker Engine, Docker Compose v2, Node.js e ferramentas operacionais, além de vincular perfis de acesso seguro via AWS Systems Manager (SSM) para dispensar o uso de chaves SSH tradicionais (.pem) e portas de gerenciamento abertas para a internet.

Representa a primeira etapa da evolução de infraestrutura da aplicação BIA, servindo como ambiente de transição entre o desenvolvimento puramente local e a arquitetura orquestrada em ECS.

---

## ☁️ Recursos AWS Envolvidos

- **Amazon EC2:** Instâncias Linux (`t3.micro`) configuradas com volume EBS de 15 GB (gp2).
- **Amazon VPC & Subnets:** Alocação de recursos em VPC default e sub-redes públicas com atribuição de IP público dinâmico.
- **Security Groups:** Grupo de segurança `bia-dev` com liberação de portas de aplicação (ex: `3001` ou `8080`) e regras de saída irrestritas.
- **AWS IAM:** Role `role-acesso-ssm` com política gerenciada `AmazonSSMManagedInstanceCore` vinculada a um Instance Profile.
- **AWS Systems Manager (SSM):** Conexão interativa via Session Manager dispensando porta 22 (SSH) aberta na borda.
- **Docker & Docker Compose:** Execução multicontêiner do backend Node.js, banco PostgreSQL e cache local.

---

## 🛠️ Pré-requisitos

1. **AWS CLI v2** instalado e autenticado na conta AWS de laboratório.
2. **AWS Session Manager Plugin** instalado na estação de trabalho para conexões interativas.
3. Permissões de IAM para criação de instâncias EC2, Security Groups, IAM Roles e Instance Profiles.
4. Repositório da aplicação BIA clonado na máquina local ou na VM remota.

---

## 🌐 Variáveis Necessárias

| Variável | Descrição | Valor de Exemplo / Padrão |
|---|---|---|
| `AWS_PROFILE` | Nome do perfil configurado no AWS CLI | `bia-dev`, `default` |
| `AWS_REGION` | Região AWS de lançamento da instância | `us-east-1` |
| `VPC_ID` | Identificador da VPC alvo | Auto-descoberto via CLI (`isDefault=true`) |
| `SUBNET_ID` | Identificador da sub-rede na zona A | Auto-descoberto via CLI (`availabilityZone=us-east-1a`) |
| `SECURITY_GROUP_NAME` | Nome do grupo de segurança do laboratório | `bia-dev` |
| `DB_PASSWORD` | Senha para o banco de dados PostgreSQL local | Definida via `.env` ou variável de sessão |

---

## 📂 Referências Relativas aos Arquivos Existentes

Os scripts operacionais e manifestos deste laboratório permanecem centralizados em seus diretórios originais para manter a compatibilidade com a aplicação BIA:

| Arquivo Original | Finalidade e Descrição |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Documento arquitetural dedicado do Desafio 01 contendo diagrama Mermaid, fluxos de comunicação, controles de segurança e limitações. |
| [`../../../scripts/lancar_ec2_zona_a.sh`](../../../scripts/lancar_ec2_zona_a.sh) | Script CLI de lançamento automatizado da EC2 com vinculação do Security Group e do Instance Profile SSM. |
| [`../../../scripts/user_data_ec2_zona_a.sh`](../../../scripts/user_data_ec2_zona_a.sh) | Bootstrap da VM: instala Docker, Compose v2, Git, jq, Node.js, cria swapfile de 4 GB e instala Python 3.11 + Astral `uv` para MCP. |
| [`../../../scripts/validar_recursos_zona_a.sh`](../../../scripts/validar_recursos_zona_a.sh) | Script de auditoria pós-criação: valida VPC, Subnet, regras de entrada/saída do SG `bia-dev` e integridade da IAM Role SSM. |
| [`../../../scripts/ec2_principal.json`](../../../scripts/ec2_principal.json) | Documento de Trust Policy que autoriza o serviço `ec2.amazonaws.com` a assumir a função IAM (`sts:AssumeRole`). |
| [`../../../scripts/criar_role_ssm.sh`](../../../scripts/criar_role_ssm.sh) | Automação que cria a IAM Role `role-acesso-ssm`, cria o instance profile e anexa a managed policy `AmazonSSMManagedInstanceCore`. |
| [`../../../scripts/start-session-bash.sh`](../../../scripts/start-session-bash.sh) | Inicia sessão Bash interativa na instância EC2 via SSM Session Manager sem expor porta SSH na internet. |
| [`../../../scripts/ligar_bia_local.sh`](../../../scripts/ligar_bia_local.sh) | Localiza a instância pela tag `Name=bia-dev` e inicia sua execução (`aws ec2 start-instances`). |
| [`../../../scripts/parar_bia_local.sh`](../../../scripts/parar_bia_local.sh) | Localiza a instância pela tag `Name=bia-dev` e interrompe sua execução (`aws ec2 stop-instances`) para contenção de custos. |
| [`../../../compose.yml`](../../../compose.yml) | Definição Docker Compose multicontêiner com serviços `server` (BIA Node.js), `database` (Postgres) e `redis` (Valkey). |
| [`../../../docs/architecture/aws-ecs-diagram.html`](../../../docs/architecture/aws-ecs-diagram.html) | Diagrama de referência visual da arquitetura de rede e computação. |

---

## 🚀 Roteiro de Execução Operacional

### Passo 1: Criação da Função IAM para o Systems Manager
```bash
# Executado a partir do diretório scripts/
cd ../../../scripts
chmod +x criar_role_ssm.sh
./criar_role_ssm.sh
```

### Passo 2: Provisionamento da Instância EC2 com User Data
```bash
# Lançamento da instância EC2 com bootstrap automatizado
chmod +x lancar_ec2_zona_a.sh
./lancar_ec2_zona_a.sh
```

### Passo 3: Validação da Infraestrutura Provisionada
```bash
# Auditoria de VPC, Subnet, Security Group e IAM Role
chmod +x validar_recursos_zona_a.sh
./validar_recursos_zona_a.sh
```

### Passo 4: Conexão Segura via SSM Session Manager
```bash
# Obter o Instance ID da instância bia-dev e conectar
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=bia-dev" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
./start-session-bash.sh "$INSTANCE_ID"
```

---

## 🛡️ Boas Práticas e Governança

- **Sem Chaves SSH em Disco:** Ao utilizar o SSM Session Manager, nenhuma chave privada `.pem` precisa ser gerada, armazenada ou distribuída entre membros da equipe.
- **Hardening de Borda:** O Security Group da instância não necessita de regra de entrada para a porta 22 (SSH).
- **Contenção de Custos:** Ao finalizar os testes, a instância deve ser desligada via `./parar_bia_local.sh` ou terminada para evitar custos desnecessários de computação.
