# Architecture Decision Records (ADRs) — Estratégias de Deploy & Resiliência

Este documento registra as decisões formais de arquitetura adotadas na Trilha 5, registrando contexto, alternativas, justificativas e consequências técnicas.

---

## 📑 Índice de Decisões

- [ADR 01: Padrão Rolling Update com minimumHealthyPercent=100 e maximumPercent=200](#adr-01-padrão-rolling-update-com-minimumhealthypercent100-e-maximumpercent200)
- [ADR 02: Ativação de ECS Deployment Circuit Breaker com Rollback Automático](#adr-02-ativação-de-ecs-deployment-circuit-breaker-com-rollback-automático)
- [ADR 03: Desacoplamento Blue/Green via Target Groups e Listeners Independentes](#adr-03-desacoplamento-bluegreen-via-target-groups-e-listeners-independentes)
- [ADR 04: Resolução de Segredos via AWS SSM Parameter Store em Task Definitions](#adr-04-resolução-de-segredos-via-aws-ssm-parameter-store-em-task-definitions)
- [ADR 05: Adoção da Rota `/api/versao` para Health Checks da Aplicação](#adr-05-adoção-da-rota-apiversao-para-health-checks-da-aplicação)
- [ADR 06: Governança Human-in-the-Loop e Hard Guardrails em Deploys Assistidos por IA](#adr-06-governança-human-in-the-loop-e-hard-guardrails-em-deploys-assistidos-por-ia)

---

### ADR 01: Padrão Rolling Update com minimumHealthyPercent=100 e maximumPercent=200

- **Status:** Aprovado / Implementado
- **Contexto:** A publicação de novas versões da aplicação BIA no ECS precisa manter a capacidade de atendimento inalterada durante a transição.
- **Decisão:** Configurar `minimumHealthyPercent = 100` e `maximumPercent = 200` no serviço ECS.
- **Consequências:**
  - *Positivas:* A aplicação nunca opera com capacidade inferior à desejada; as novas tarefas são iniciadas e validadas antes do encerramento das antigas.
  - *Negativas:* Requer capacidade excedente de vCPU e memória temporária no cluster durante o deployment.

---

### ADR 02: Ativação de ECS Deployment Circuit Breaker com Rollback Automático

- **Status:** Aprovado / Modelado em Templates
- **Contexto:** Releases defeituosos podem falhar consecutivamente na inicialização, causando degradação ou estado indefinido caso o operador humano não intervenha a tempo.
- **Decisão:** Ativar `deploymentCircuitBreaker: { enable: true, rollback: true }`.
- **Consequências:**
  - *Positivas:* O próprio control plane do ECS detecta após 3 falhas de container e reverte o serviço para a versão anterior estável sem necessidade de intervenção humana.
  - *Negativas:* O tempo de reação é atrelado ao threshold de falhas consecutivas, dependendo da velocidade de reinício dos containers.

---

### ADR 03: Desacoplamento Blue/Green via Target Groups e Listeners Independentes

- **Status:** Aprovado / Documentado e Modelado
- **Contexto:** Grandes atualizações estruturais ou de banco necessitam de testes prévios isolados antes de expor os usuários de produção.
- **Decisão:** Modelar a arquitetura Blue/Green com dois Target Groups distintos (`tg-bia-blue` e `tg-bia-green`) e listeners dedicados para Produção (porta 80) e Teste (porta 8080).
- **Consequências:**
  - *Positivas:* Permite validação end-to-end em ambiente idêntico ao de produção; cutover e rollback atômicos ou ponderados via Application Load Balancer.
  - *Negativas:* Duplicação de custos de contêineres e necessidade de controle rigoroso do tempo de término do ambiente antigo.

---

### ADR 04: Resolução de Segredos via AWS SSM Parameter Store em Task Definitions

- **Status:** Aprovado / Implementado em Templates
- **Contexto:** A task definition histórica da aplicação continha a senha do PostgreSQL em texto claro (`DB_PWD`).
- **Decisão:** Substituir senhas no bloco `environment` por referências seguras via `secrets` apontando para o AWS Systems Manager Parameter Store (`valueFrom: arn:aws:ssm:...`).
- **Consequências:**
  - *Positivas:* Elimina credenciais em texto claro de manifestos e repositórios; facilita rotação de senhas sem alterar o arquivo de release.
  - *Negativas:* Requer permissão `ssm:GetParameters` na `ecsTaskExecutionRole`.

---

### ADR 05: Adoção da Rota `/api/versao` para Health Checks da Aplicação

- **Status:** Aprovado / Corrigido
- **Contexto:** A documentação anterior utilizava o endpoint fictício `/health`, enquanto a aplicação Express expõe a rota oficial `/api/versao` para status da API e `/` para a interface web.
- **Decisão:** Ajustar formalmente os health checks nos Target Groups e Task Definitions para a rota real `/api/versao`.
- **Consequências:**
  - *Positivas:* Alinhamento exato entre a infraestrutura de balanceamento e o código-fonte da aplicação BIA.
  - *Negativas:* Nenhuma.

---

### ADR 06: Governança Human-in-the-Loop e Hard Guardrails em Deploys Assistidos por IA

- **Status:** Proposto / Conceitual
- **Contexto:** O uso de Foundation Models (Amazon Bedrock) para validar telemetria introduz riscos de alucinação e decisões equivocadas de release.
- **Decisão:** A IA atuará exclusivamente em modo consultivo (read-only); qualquer violação de regras determinísticas básicas (erros 5XX > 0 ou hosts não saudáveis) aborta a release sem consultar a IA; o cutover final requer aprovação humana obrigatória.
- **Consequências:**
  - *Positivas:* Máxima segurança e auditabilidade; a IA agrega análise qualitativa sem assumir risco autônomo sobre a infraestrutura de produção.
  - *Negativas:* Não atinge automação 100% autônoma (zero-touch), mantendo o operador na cadeia de aprovação.
