# Desafio 01 — N8N Single-Mode com Auto-Recovery (Self-Healing)

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** N8N na AWS (Plataforma de Automação & Workflows)<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Documentado e Estruturado (Evidência histórica homologada na AWS)<br>
> **Adaptações D2NS:** Arquitetura single-mode com auto-recovery (self-healing) no ECS, persistência externa em Amazon RDS PostgreSQL e redução de custos sem NAT Gateway.<br>
> **Laboratório Histórico Original:** [`n8n-lab/`](../../../n8n-lab/)

---

## 🎯 Objetivo Arquitetural

Implantar a plataforma de automação **N8N** na AWS utilizando o modelo monólito otimizado para laboratório educacional e baixo custo operacional. A aplicação executa em container único gerenciado pelo **Amazon ECS** com capacidade **EC2**, exposta através de um **Application Load Balancer (ALB)** com terminação HTTPS (porta 443), banco de dados dedicado **Amazon RDS PostgreSQL** e domínio próprio sob certificado SSL/TLS gerenciado.

---

## ☁️ Recursos AWS Envolvidos

- **Amazon ECS Cluster:** `cluster-n8n-d2n` operando com Capacity Provider vinculado ao Auto Scaling Group.
- **Amazon EC2:** 1 instância `t3.micro` (1 vCPU, 1 GB RAM) executando a AMI AL2023 ECS-Optimized.
- **Application Load Balancer (ALB):** Internet-facing, ouvindo na porta HTTPS 443 com certificado ACM e roteando requisições para o Target Group.
- **Target Group:** Tipo `instance`, mapeamento dinâmico de portas efêmeras do host e verificação de saúde nativa em `/healthz`.
- **Amazon RDS PostgreSQL:** Instância dedicada `db.t3.micro` (20 GB gp2, PostgreSQL 16.x) privada na VPC com criptografia TLS ativa.
- **AWS Systems Manager Parameter Store:** Parâmetros `SecureString` para `/n8n/db_password` e `/n8n/encryption_key`.
- **Amazon Route 53:** Registro Alias A apontando o domínio customizado (ex.: `n8n.<SEU_DOMINIO>`) para o DNS do ALB.
- **Amazon CloudWatch Logs:** Log Group `/ecs/n8n-ec2` coletando os logs do container N8N.

---

## ⚙️ Características do Single-Mode com Auto-Recovery

> [!IMPORTANT]
> **Natureza da Arquitetura: Self-Healing vs. Alta Disponibilidade Real (Multi-AZ):**<br>
> Este laboratório opera com 1 única instância EC2 e 1 única Task ECS ativa (`desiredCount=1`) conectada a um banco RDS Single-AZ.<br>
> Ele **não é tolerante à indisponibilidade de uma Zona de Disponibilidade inteira**, mas entrega **Recuperação Automática (Self-Healing)** contra falhas locais:
> - **Crash do Container N8N:** O ECS Service detecta a falha do container e agenda uma nova task na mesma EC2 (~30–60 segundos).
> - **Falha de Hardware da Instância EC2:** O Auto Scaling Group detecta a máquina não íntegra, encerra a instância degradada e provisiona um novo host no cluster, reagendando a task (~3–5 minutos).

---

## 🛠️ Decisões Arquiteturais Fundamentais

| Decisão Técnica | Escolha | Justificativa de Engenharia |
|---|---|---|
| **Modo de Rede ECS** | `bridge` | Permite saída direta à internet pelo IP público do host EC2 para execução de workflows e webhooks externos, **eliminando a necessidade de NAT Gateway** (~$32/mês de economia). |
| **Port Mapping** | Dinâmico (`hostPort: 0 -> containerPort: 5678`) | O ECS Agent aloca portas efêmeras dinâmicas no host (32768–65535) e as registra automaticamente no Target Group via ALB. |
| **Health Check** | Path `/healthz` (HTTP 200) | Endpoint nativo da API do N8N avaliado na porta dinâmica mapeada pelo ALB. |
| **Persistência de Dados** | RDS PostgreSQL Dedicado | Garante que workflows, credenciais e histórico de execuções persistam mesmo se o container ou a instância forem totalmente destruídos. |
| **Injeção de Segredos** | SSM Parameter Store (`SecureString`) | Senhas e chaves criptográficas são injetadas em tempo de inicialização pelo ECS Agent via Task Execution Role, sem constar em texto claro no manifesto. |
| **Imagem do Container** | `n8nio/n8n:2.22.6` | Versão oficial e estável homologada no Docker Hub para arquitetura `x86_64`. |

---

## 📄 Template Fornecido

O modelo sanitizado de Task Definition para implantação no Amazon ECS está disponível em:

👉 [`templates/task-def.example.json`](templates/task-def.example.json)

> [!WARNING]
> **Substituição de Placeholders:**<br>
> O template utiliza identificadores genéricos como `<SUA_CONTA_AWS>`, `<SUA_REGIAO_AWS>`, `<SEU_ENDPOINT_RDS_POSTGRES>` e `<SEU_DOMINIO>`. Substitua todos os placeholders pelas informações do seu ambiente antes de registrar a Task Definition no Amazon ECS.

---

## 🚀 Roteiro Didático de Implantação

O ciclo de vida do ambiente Single-Mode contempla as seguintes etapas sequenciais:

1. **Parâmetros SSM:** Criar os parâmetros `SecureString` no Systems Manager Parameter Store:
   ```bash
   aws ssm put-parameter --name "/n8n/db_password" --value "<SENHA_FORTE>" --type SecureString
   aws ssm put-parameter --name "/n8n/encryption_key" --value "<CHAVE_ALEATORIA_32_CHARS>" --type SecureString
   ```
2. **Security Groups:** Criar e associar os grupos de segurança com regras estritas:
   - `SG ALB`: Entrada TCP 443 aberta à internet (`0.0.0.0/0`).
   - `SG EC2`: Entrada portas efêmeras (32768–65535) liberada estritamente a partir do `SG ALB`.
   - `SG RDS`: Entrada TCP 5432 liberada estritamente a partir do `SG EC2`.
3. **RDS PostgreSQL:** Provisionar a instância de banco de dados (`db.t3.micro`, Single-AZ, não pública).
4. **Target Group & ALB:** Provisionar o balanceador HTTPS e Target Group do tipo `instance` com health check em `/healthz`.
5. **Auto Scaling & ECS Capacity Provider:** Provisionar o Launch Template (AMI AL2023 ECS-Optimized), Auto Scaling Group (`desired=1`) e vincular o Capacity Provider ao cluster ECS.
6. **Task Definition & ECS Service:** Registrar o manifesto sanitizado [`templates/task-def.example.json`](templates/task-def.example.json) e iniciar o ECS Service com `desiredCount=1`.
7. **Route 53:** Criar registro Alias A apontando `n8n.<SEU_DOMINIO>` para o DNS do Application Load Balancer.

---

## ⚠️ Limitações do Modelo Single-Mode

Embora econômico e estável para volumes moderados, o Single-Mode apresenta gargalos operacionais:
1. **Concorrência entre Interface e Execuções:** A interface web, a API interna e os workflows concorrem pela mesma CPU e memória (650 MiB soft limit).
2. **Impacto de Workflows Pesados:** Processamentos demorados ou loops de dados massivos podem travar a recepção de novos webhooks ou degradar o editor visual.

Essas limitações motivaram a criação do **Desafio 02 (Queue Mode)**, que desacopla totalmente a camada de atendimento da camada de execução em fila distribuída.

---

## 🛡️ Matriz de Maturidade

| Componente | Classificação | Evidência Histórica Documentada |
|---|:---:|---|
| **Manifesto Task Definition** | ✅ Implementado | Validado e registrado com sucesso como `task-def-n8n-d2n` no cluster ECS. |
| **Self-Healing de Container** | ✅ Implementado | Recuperação automática comprovada em crash simulado de container na mesma EC2. |
| **Self-Healing de Instância** | ✅ Implementado | Substituição automática de máquina íntegra pelo ASG com reagendamento da task. |
| **Economia de Rede (Sem NAT)** | ✅ Implementado | Operação em modo `bridge` com tráfego de saída validado via IP público do host. |
