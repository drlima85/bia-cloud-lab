# Desafio 01 — Atualização Gradual (Rolling Update) no ECS

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Estratégias de Deploy & Resiliência<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** 🟡 Implementado e Documentado (Validação Contínua Pendente)<br>
> **Adaptações D2NS:** Controle estrito de capacidade com minimumHealthyPercent=100 e maximumPercent=200, draining de conexões no ALB parametrizado e script defensivo de deploy com commit hash Git.

---

## 🎯 Objetivo Arquitetural

Implementar, documentar e analisar o padrão de atualização contínua e gradual (**Rolling Update**) para os contêineres da aplicação BIA no Amazon ECS, garantindo que novas versões da imagem Docker sejam implantadas com controle estrito do percentual mínimo de integridade (`minimumHealthyPercent`) e capacidade máxima permitida (`maximumPercent`), reduzindo riscos de indisponibilidade durante o ciclo de publicação.

---

## 📊 Matriz de Maturidade e Evidências

Em aderência às boas práticas de governança técnica, os artefatos desta trilha são classificados com precisão em quatro dimensões:

| Dimensão | Situação | Detalhamento |
|---|:---:|---|
| **Funcionalidade em Código** | ✅ Implementada | Automação completa no script [deploy-ecs.sh](../scripts/deploy-ecs.sh), suportando geração de tags baseadas em commit hash Git, push ao Amazon ECR, criação de nova revisão de Task Definition e chamada de atualização do serviço no ECS. |
| **Execução Histórica** | ✅ Documentada | Execuções realizadas no contexto dos laboratórios da Formação AWS e do desenvolvimento do BIA Cloud Lab, com acompanhamento das transições de status das tarefas e espera de estabilização via `aws ecs wait services-stable`. |
| **Testes Comprovados** | 🟡 Parcial | Validação funcional da substituição sequencial de tasks no cluster ECS e resposta HTTP 200 no endpoint de checagem. |
| **Validações Pendentes** | ⚪ Planejada | **Zero Downtime formalmente comprovado sob carga:** Execução de testes de carga contínua (ex: Locust, k6 ou JMeter) durante a janela de transição de tarefas para certificar ausência absoluta de erros HTTP 502/503/504 ou desconexões TCP. *A mera existência de scripts de deploy e contêineres de checagem não constitui prova empírica de zero downtime.* |

---

## ⚙️ Mecânica do Rolling Update no Amazon ECS

No modelo de **Rolling Update**, o Amazon ECS substitui gradualmente as instâncias da Task Definition antiga pelas instâncias da nova Task Definition, mantendo o serviço operacional durante todo o processo.

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Operador / CI-CD
    participant ECS as Amazon ECS Service
    participant ALB as Application Load Balancer
    participant OldTask as Task v1 (Ativa)
    participant NewTask as Task v2 (Nova)

    Dev->>ECS: aws ecs update-service --task-definition bia:v2
    Note over ECS: Avalia maximumPercent (200%) e minimumHealthyPercent (100%)
    ECS->>NewTask: Provisiona nova tarefa (PENDING -> RUNNING)
    ECS->>ALB: Registra Task v2 no Target Group
    loop Health Checks
        ALB->>NewTask: GET /api/versao (healthCheckGracePeriodSeconds)
        NewTask-->>ALB: HTTP 200 OK (Healthy)
    end
    Note over ALB,NewTask: Task v2 recebe tráfego de produção
    ECS->>ALB: Inicia Deregistration da Task v1 (Connection Draining)
    Note over ALB,OldTask: ALB para de enviar novas conexões para Task v1;<br/>aguarda conexões ativas encerrarem
    OldTask-->>ALB: Conexões finalizadas (ou timeout de draining)
    ECS->>OldTask: Envia SIGTERM (stopTimeout) e encerra Task v1 (STOPPED)
    ECS-->>Dev: Deployment concluído (services-stable)
```

### 1. Parâmetros Críticos de Configuração

Os dois parâmetros que governam a velocidade, a segurança e a disponibilidade durante o deploy são:

- **`minimumHealthyPercent` (ex: 100%):**
  - Define o limite inferior de tarefas no estado `RUNNING` como percentual da capacidade desejada (`desiredCount`).
  - Em um serviço com `desiredCount = 2` e `minimumHealthyPercent = 100`, o ECS **nunca** descerá abaixo de 2 tarefas ativas (`ceil(2 * 100 / 100) = 2`).
  - Se configurado para 50%, o ECS poderia encerrar 1 tarefa antes de provisionar a nova, operando temporariamente com capacidade reduzida.

- **`maximumPercent` (ex: 200%):**
  - Define o limite superior de tarefas permitidas durante a implantação.
  - Com `desiredCount = 2` e `maximumPercent = 200`, o ECS pode manter até 4 tarefas simultâneas (`floor(2 * 200 / 100) = 4`).
  - Isso autoriza o provisionamento antecipado das 2 tarefas v2 enquanto as 2 tarefas v1 continuam atendendo usuários.

### 2. Tabela de Dimensionamento de Tarefas

| Cenário (`desiredCount = 2`) | minHealthy % | max % | Tasks no Início do Deploy | Tasks no Pico do Deploy | Tasks no Fim | Resiliência a Picos |
|---|:---:|:---:|:---:|:---:|:---:|---|
| **Padrão de Alta Resiliência** | 100% | 200% | 2 (v1) | 4 (2 v1 + 2 v2) | 2 (v2) | Capacidade total mantida durante todo o processo. |
| **Conservação de Recursos** | 50% | 100% | 2 (v1) | 2 (1 v1 + 1 v2) | 2 (v2) | Capacidade de atendimento cortada pela metade durante o deploy. |
| **Sem Capacidade Adicional** | 100% | 100% | 2 (v1) | Impossível atualizar | 2 (v1) | O ECS bloqueia o rollout porque não há margem para criar tarefas. |

### 3. Impacto na Capacidade da Infraestrutura Subjacente

- **ECS com AWS Fargate (Serverless):**
  - A AWS provisiona a infraestrutura de computação de forma elástica e sob demanda.
  - Subir de 2 para 4 tarefas temporariamente requer apenas quota suficiente na conta AWS (número de tarefas Fargate concorrentes).
- **ECS com EC2 Instances (Cluster Gerenciado):**
  - Se o cluster possui instâncias EC2 com recursos limitados (ex: apenas 2 instâncias t3.medium com 2 vCPUs e 4 GB de memória), o cluster precisa possuir vCPU e memória livres para hospedar as tarefas extras.
  - Caso a memória ou CPU do cluster seja insuficiente para o pico de 200%, as novas tarefas ficam presas no status `PROVISIONING` por falta de recursos, travando o deployment.

---

## 🛡️ Integração com Application Load Balancer (ALB)

Para mitigar a ocorrência de respostas de erro durante a troca de versão, dois mecanismos do ALB são fundamentais:

### 1. Connection Draining (Deregistration Delay)

Quando o ECS decide descomissionar uma tarefa antiga (v1):
1. O ALB altera o status do target para `draining`.
2. O balanceador para imediatamente de encaminhar **novas** requisições para o target v1.
3. Requisições em andamento (in-flight requests) recebem um intervalo configurável (`deregistration_delay.timeout_seconds`) para concluir o processamento normalmente.
4. Ao término do delay (ou quando não houver mais conexões ativas), o target é completamente desregistrado.

> **Recomendação:** O valor padrão do ALB é 300 segundos. Para APIs REST stateless de baixa latência como a BIA, recomenda-se ajustar este valor para **15 a 30 segundos**, reduzindo o tempo total do ciclo de deploy sem interromper clientes.

### 2. Período de Graça de Health Check (`healthCheckGracePeriodSeconds`)

- Evita que o ECS mate prematuramente um container que ainda está inicializando (boot do Node.js, compilação de assets ou conexão com o banco de dados).
- No serviço BIA, o período de graça é parametrizado em **60 segundos** (`healthCheckGracePeriodSeconds: 60`), concedendo tempo para a aplicação subir e responder `HTTP 200` no endpoint `/api/versao` (rota real da API que retorna a versão ativa; em arquiteturas genéricas é comum o uso do caminho `/health`).

---

## 🛠️ Automações Disponíveis no Repositório

### 1. Script Principal: `deploy-ecs.sh`

Localizado em [deploy-ecs.sh](../scripts/deploy-ecs.sh), este script orquestra o pipeline local:

```bash
# Execução padrão (captura git commit hash, faz build, push e update do serviço)
./deploy-ecs.sh deploy -r us-east-1 -c cluster-bia -s service-bia -f task-def-bia

# Fluxo executado internamente:
# 1. get_commit_hash (últimos 7 caracteres Git)
# 2. docker build -t <ecr_uri>:<commit_hash>
# 3. docker push <ecr_uri>:<commit_hash>
# 4. aws ecs register-task-definition (com nova imagem)
# 5. aws ecs update-service --service service-bia --task-definition task-def-bia:<revision>
# 6. aws ecs wait services-stable
```

### 2. Utilitário de Monitoramento de Disponibilidade

A trilha disponibiliza o script especializado de telemetria contínua em [check-availability.sh](../scripts/check-availability.sh) (evolução dos utilitários legados de checagem do laboratório):

```bash
# Executa checagem contínua via curl com medição de latência e sumário
./scripts/check-availability.sh -i 2
```

O contêiner emite a cada 5 segundos:
```text
Status: 200 - Hora: 15:30:00
Status: 200 - Hora: 15:30:05
```

> **Nota de Auditoria:** Este utilitário realiza checagens sequenciais simples a cada 5 segundos. Para testes de resiliência e validação empírica de Zero Downtime sob alta concorrência, é necessário complementar com ferramentas de teste de carga contínuo com concorrência paralela (concorrência > 50 requisições/segundo).

---

## 📁 Templates Sanitizados

| Arquivo | Descrição |
|---|---|
| [templates/task-def.example.json](templates/task-def.example.json) | Template parametrizado da Task Definition da BIA, contendo logging CloudWatch, porta 8080 e segredos protegidos via AWS Systems Manager Parameter Store. |
| [templates/service-rolling.example.json](templates/service-rolling.example.json) | Template de configuração do serviço Amazon ECS com `minimumHealthyPercent: 100` e `maximumPercent: 200`. |

---

## 🔍 Limitações Conhecidas e Próximos Passos

1. **Validação de Carga Contínua:** Implementar rotina com ferramenta de stress test (ex: k6 ou Artillery) disparando tráfego constante contra o ALB durante todo o ciclo de `update-service`, registrando métricas de percentil (p95, p99) e eventuais erros 5xx.
2. **Afinação do Deregistration Delay:** Validar o tempo ideal de drenagem no Target Group para conciliar rapidez de implantação e encerramento limpo de conexões.
3. **Rollback Automatizado:** Implementar detecção automática de falha na nova versão, tema abordado no [Desafio 02 — Rollback e Deployment Circuit Breaker](../02-deploy-rollback-circuit-breaker/README.md).
