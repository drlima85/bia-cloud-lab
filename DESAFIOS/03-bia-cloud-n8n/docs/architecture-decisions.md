# Architecture Decision Records (ADRs) — N8N na AWS

Este documento registra as principais decisões arquiteturais tomadas durante a concepção, homologação e organização da infraestrutura do N8N na nuvem AWS.

---

## Índice dos ADRs

1. [ADR-01: Adoção do Amazon ECS com Capacidade EC2 em Modo de Rede Bridge](#adr-01-adoção-do-amazon-ecs-com-capacidade-ec2-em-modo-de-rede-bridge)
2. [ADR-02: Uso do ElastiCache Valkey com TLS e AUTH Token como Broker BullMQ](#adr-02-uso-do-elasticache-valkey-com-tls-e-auth-token-como-broker-bullmq)
3. [ADR-03: Desacoplamento da Camada de Persistência com Amazon RDS PostgreSQL Privado](#adr-03-desacoplamento-da-camada-de-persistência-com-amazon-rds-postgresql-privado)
4. [ADR-04: Segregação Funcional de Tarefas em Main (Web/UI) e Workers (Execução)](#adr-04-segregação-funcional-de-tarefas-em-main-webui-e-workers-execução)
5. [ADR-05: Injeção de Segredos em Runtime via AWS Systems Manager Parameter Store](#adr-05-injeção-de-segredos-em-runtime-via-aws-systems-manager-parameter-store)
6. [ADR-06: Governança IAM Estrita com Políticas Temporárias e Menor Privilégio](#adr-06-governança-iam-estrita-com-políticas-temporárias-e-menor-privilégio)

---

## ADR-01: Adoção do Amazon ECS com Capacidade EC2 em Modo de Rede Bridge

### Contexto
O N8N precisa executar de forma contínua em ambiente de containers na AWS. As alternativas avaliadas foram:
1. Amazon ECS com AWS Fargate (modo `awsvpc`).
2. Amazon ECS com capacidade EC2 em modo `bridge` com Dynamic Port Mapping.
3. Instância EC2 isolada executando Docker Compose tradicional.

### Decisão
Optou-se pelo **Amazon ECS com capacidade EC2 em modo `bridge`**.

### Consequências
* **Positivas:**
  * **Custo Reduzido:** Operação contínua de laboratório muito mais econômica em instâncias `t3.micro` / `t3.small` em comparação à tarifação horária por vCPU/GB do Fargate.
  * **Sem Custo de NAT Gateway:** No modo `bridge`, o container utiliza a pilha de rede e o IP público da instância EC2 nas subnets públicas para tráfego de saída à internet (necessário para nós que chamam APIs externas), eliminando o alto custo fixo de um NAT Gateway privado.
  * **Zero Conflito de Portas:** O Dynamic Port Mapping aloca portas dinâmicas efêmeras (32768–65535) no host e as registra automaticamente no Target Group do ALB.
* **Negativas / Trade-offs:**
  * Necessidade de gerenciar a instância subjacente (Launch Template, AMI ECS-Optimized e Auto Scaling Group).
  * Menor isolamento de rede entre containers no mesmo host se comparado ao modo `awsvpc`.

---

## ADR-02: Uso do ElastiCache Valkey com TLS e AUTH Token como Broker BullMQ

### Contexto
O N8N utiliza o **BullMQ** como gerenciador de filas para o Queue Mode, exigindo um backend em memória compatível com Redis. A AWS disponibiliza o Amazon ElastiCache Valkey (fork de código aberto do Redis sob licença BSD).

### Decisão
Adotar o **Amazon ElastiCache Valkey (versão 7.2, nó `cache.t4g.micro`)**, com Criptografia em Trânsito (TLS) e Token de Autenticação (`AUTH Token`) ativados obrigatoriamente.

### Consequências
* **Positivas:**
  * **100% de Compatibilidade:** Totalmente compatível com a API Redis utilizada pela biblioteca BullMQ do N8N.
  * **Eficiência e Custo:** A arquitetura baseada em processadores AWS Graviton2 (`t4g.micro`) oferece alta performance por ciclo com baixo consumo de memória.
  * **Segurança Reforçada:** TLS impede a interceptação de dados de workflows trafegando pela rede VPC, e o AUTH Token impede acessos não autorizados mesmo dentro da rede interna.
* **Negativas / Trade-offs:**
  * O nó `cache.t4g.micro` em Single-AZ não possui replicação de alta disponibilidade no laboratório; caso a máquina falhe, mensagens transitórias na fila são perdidas (mas workflows concluídos permanecem no RDS).

---

## ADR-03: Desacoplamento da Camada de Persistência com Amazon RDS PostgreSQL Privado

### Contexto
O N8N suporta SQLite por padrão, mas a documentação oficial da ferramenta contraindica SQLite para ambientes com concorrência ou em Queue Mode, recomendando PostgreSQL.

### Decisão
Provisionar uma instância dedicada do **Amazon RDS PostgreSQL (`db.t3.micro`, versão 16.x)** em subnets da VPC com `PubliclyAccessible: false`.

### Consequências
* **Positivas:**
  * **Suporte Concorrente:** Permite que a task Main e múltiplos Workers realizem leituras e escritas concorrentes sem travar o banco.
  * **Isolamento de Acesso:** Banco 100% privado na VPC, acessível exclusivamente a partir do Security Group das instâncias ECS (`n8n-ec2`).
  * **Persistência Confiável:** Schemas, histórico de execuções, nós e credenciais criptografadas permanecem preservados independentemente do ciclo de vida dos containers.
* **Negativas / Trade-offs:**
  * Custo associado ao provisionamento do banco relacional gerenciado e consumo de conexões simultâneas que deve ser dimensionado para o número de workers.

---

## ADR-04: Segregação Funcional de Tarefas em Main (Web/UI) e Workers (Execução)

### Contexto
Em Single-Mode, quando um fluxo de automação realiza transformações pesadas de dados ou chamadas HTTP bloqueantes, o thread principal do Node.js pode sofrer degradação, tornando a interface inacessível e atrasando a resposta de webhooks.

### Decisão
Segregar o ambiente em dois serviços ECS desacoplados:
1. `svc-n8n-main`: 1 task responsável pelo editor web, UI, webhook receiver e enfileiramento (`OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true`).
2. `svc-n8n-worker`: 2 tasks dedicadas exclusivamente a drenar mensagens do BullMQ e executar a lógica computacional dos fluxos (`command: ["worker", "--concurrency=5"]`).

### Consequências
* **Positivas:**
  * Alta disponibilidade da UI e dos webhooks mesmo durante a execução de pipelines massivas de dados.
  * Capacidade de escalabilidade horizontal independente: é possível escalar apenas os workers sob demanda de fila sem alterar a quantidade de tasks Main.
* **Negativas / Trade-offs:**
  * Maior consumo de memória agregada no host ECS (necessitou evolução de `t3.micro` para `t3.small`).

---

## ADR-05: Injeção de Segredos em Runtime via AWS Systems Manager Parameter Store

### Contexto
O N8N requer segredos sensíveis para inicialização: senha do banco de dados PostgreSQL (`DB_POSTGRESDB_PASSWORD`), chave de encriptação dos fluxos (`N8N_ENCRYPTION_KEY`) e token de autenticação da fila (`QUEUE_BULL_REDIS_PASSWORD`).

### Decisão
Armazenar todos os segredos no **AWS Systems Manager Parameter Store** com tipo `SecureString` (criptografados com AWS KMS) e injetá-los diretamente nas especificações de container (`secrets`) das Task Definitions via ECS Agent.

### Consequências
* **Positivas:**
  * **Sem Credenciais em Texto Claro:** Nenhum arquivo versionado no Git (`task-definition.json`, `docker-compose.yml`, scripts) contém senhas reais.
  * **Resolução Segura pelo Agente:** O ECS Agent recupera o segredo via API SSM no momento do start do container e o injeta como variável de ambiente em memória, sem persistência em disco.
* **Negativas / Trade-offs:**
  * A IAM Role de execução (`n8n-task-execution-role`) necessita de permissão explícita para `ssm:GetParameters` nos recursos específicos.

---

## ADR-06: Governança IAM Estrita com Políticas Temporárias e Menor Privilégio

### Contexto
É prática comum em tutoriais de laboratório a concessão de `AdministratorAccess` para usuários de estudo, criando vulnerabilidades e risco de vazamento acidental de permissões de alto impacto.

### Decisão
Implementar uma governança rigorosa de identidades:
1. Criar políticas gerenciadas com escopo cirúrgico (`01-policy-prevalidation-readonly` e `02-policy-deploy`).
2. Restringir permissões de criação e deleção estritamente a recursos com prefixo `n8n-*`.
3. Delimitar ações no Route 53 com condições estritas de tipo de registro (`A`), nome (`n8n.*`) e hosted zone específica.

### Consequências
* **Positivas:**
  * Previne alterações acidentais em outros projetos da conta (como a infraestrutura da aplicação BIA).
  * Facilita a auditoria de conformidade e o desprovisionamento completo dos recursos pós-teste.
* **Negativas / Trade-offs:**
  * Maior complexidade inicial na definição e teste das políticas granulares antes do provisionamento.
