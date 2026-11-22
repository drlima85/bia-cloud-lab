# Scripts Utilitários — Estratégias de Deploy & Resiliência no Amazon ECS

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Estratégias de Deploy & Resiliência (`04-deploy-strategies`)<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Validado Sintaticamente e Homologado para `us-east-2`<br>
> **Padrão Obrigatório Formação AWS:** O comando `deploy.sh` executa **Docker Build** e **ECR Push** por padrão antes de atualizar o Amazon ECS.

---

## 🎯 Arquitetura Modular e Especializada

A suite de scripts adota o princípio de responsabilidade única (Single Responsibility Principle), separando as rotinas em scripts executáveis especializados que compartilham utilitários e configurações centrais, preservando uma fachada de compatibilidade unificada:

```
scripts/
├── common.sh                 <-- [BIBLIOTECA COMPARTILHADA] Logging, STS/Conta, Git, Cores e Env Loader
├── deploy.conf               <-- [CONFIGURAÇÃO CENTRAL] Ambientes (app, alb, didatico) e parâmetros padrão
├── deploy.sh                 <-- [DEPLOYMENT CI/CD] Build Docker + ECR Push + Register Task Def + Rollout + Smoke Test
├── rollback.sh               <-- [ROLLBACK DIRETO] Reversão controlada (interativa ou direta) sem build/push
├── list-versions.sh          <-- [LISTAGEM REAL] Tabela de revisões no ECS Control Plane, status, imagens e tags
├── check-availability.sh     <-- [MONITOR HTTP] Telemetria de latência e disponibilidade contínua (com -E)
├── deploy-ecs.sh             <-- [FACHADA UNIFICADA] Ponto de entrada de retrocompatibilidade para automações
└── test-security-checks.sh   <-- [SUÍTE DE TESTES] 18 testes automatizados de segurança, resiliência e integração
```

---

## 🏗️ 1. Módulo Compartilhado (`common.sh`) e Configurações (`deploy.conf`)

Todos os scripts consomem as configurações de `deploy.conf` e as funções de utilidade de `common.sh`:

- **Conta AWS Autorizada Mandatória:** Configurada via `AUTHORIZED_ACCOUNT` ou `AWS_ACCOUNT_ID` (em `.env` ou variável de ambiente; bloqueio imediato se a identidade STS divergir ou se nenhuma conta for informada em live mode).
- **Perfil e Região Padrão:** Configuráveis via `AWS_PROFILE` e `AWS_REGION` (com defaults `agy-aws-lab` e `us-east-2`).
- **Ambientes Homologados (`-E | --env`):**
  - `app`: Cluster `cluster-bia-app` / Serviço `service-bia-cloud-app` (Principal com ALB + EC2).
  - `alb`: Cluster `cluster-bia-app` / Serviço `service-bia-cloud-alb` (Secundário).
  - `didatico`: Cluster `cluster-bia` / Serviço `service-bia` (Ambiente conceitual da Formação AWS).

---

## 🚀 2. Deploy Contínuo (`deploy.sh`)

Executa o fluxo completo de publicação contínua:
1. **Pre-flight Checks (Fail-Fast):**
   - Valida identidade STS e conformidade da conta.
   - Valida o repositório ECR (`bia-cloud-lab`).
   - Inspeciona o working tree da aplicação contra `.dockerignore` (bloqueia contexto sujo sem commit).
   - Inspeciona a Task Definition base (`:15` homologada por padrão; **bloqueia estritamente a revisão defeituosa `:16`**).
   - Valida unicidade e existência do contêiner configurado (`bia-cloud-app`).
2. **Build Docker e Push ECR:**
   - Compila a imagem localmente utilizando a tag imutável do Git commit SHA HEAD (ou `-t <TAG>`).
   - Realiza login seguro no ECR e envia as camadas da imagem.
3. **Registro da Nova Task Definition:**
   - Executa transformação cirúrgica com `jq`, preservando `placementConstraints`, `requiresCompatibilities`, variáveis e segredos SSM.
   - Remove apenas os metadados de resposta da AWS (`del(...)`).
   - Altera exclusivamente o campo `image` do contêiner configurado.
4. **Atualização do Serviço e Monitoramento:**
   - Dispara a atualização do serviço ECS (`update-service`).
   - Monitora o `rolloutState` e detecta autonomamente o disparo do **ECS Deployment Circuit Breaker** (`rolloutState == FAILED`), realizando diagnóstico read-only e saindo com **código 2**.
   - Se `desiredCount == 0`, bloqueia a homologação com **código 1**.
   - Aguarda a estabilização completa do cluster (`wait services-stable`).
5. **Smoke Test com Retentativas Transitórias:**
   - Valida o endpoint do ALB (`GET /api/versao`).
   - Em caso de falha persistente de negócio, dispara auto-rollback emergencial e sai com **código 3**.

### Exemplos de Execução:
```bash
# Deploy padrão com a baseline estável :15:
./deploy.sh --base-revision 15

# Simulação segura não-destrutiva (Dry-Run):
./deploy.sh --dry-run

# Deploy reutilizando imagem já existente no ECR (sem rebuild):
./deploy.sh --skip-build -t 83a1f07
```

---

## 🛡️ 3. Rollback Controlado (`rollback.sh`)

Especializado na reversão direta e imediata para uma revisão anterior homologada:
- **Garantia de Rollback Enxuto:** **NÃO** executa `docker build`, **NÃO** executa `docker push`, **NÃO** registra nova Task Definition.
- **Proteção Rígida:** Rejeita categoricamente a revisão contaminada `:16` com erro e `exit 1`.
- **Modo Direto ou Interativo:**
  - Se `-r <REV>` for informado, valida o status `ACTIVE` e comuta imediatamente.
  - Se `-r` não for fornecido em terminal interativo, executa `list-versions.sh` e solicita o número da revisão ao operador.
- **Comutação Direta:** Executa `aws ecs update-service --task-definition <FAMILIA>:<REV>`, aguarda `services-stable` e executa Smoke Test de confirmação.

### Exemplos de Execução:
```bash
# Rollback direto para a revisão estável 15:
./rollback.sh -r 15

# Simulação de rollback (Dry-Run):
./rollback.sh -r 15 --dry-run

# Modo interativo com consulta de versões:
./rollback.sh
```

---

## 📋 4. Listagem Real de Revisões (`list-versions.sh`)

Consulta o plano de controle do Amazon ECS e apresenta o histórico detalhado das revisões da família:
- Identifica a revisão ativa no serviço com o marcador `--> [ATIVA NO SERVIÇO]`.
- Identifica a revisão defeituosa `:16` com o marcador `⚠️ [FALHA INDUZIDA FASE 2]`.
- Exibe Status, Data de Registro em UTC e Imagem/Tag associada.
- Suporte a modo `--dry-run` com simulação didática quando a sessão STS estiver offline.

### Exemplos de Execução:
```bash
# Listar as últimas 10 revisões do ambiente padrão (app):
./list-versions.sh

# Listar as últimas 5 revisões do ambiente secundário (alb):
./list-versions.sh -E alb --limit 5
```

---

## ⏱️ 5. Checagem Contínua de Disponibilidade (`check-availability.sh`)

Mede latência, códigos HTTP e taxa de disponibilidade com relatórios em tempo real:
- Suporta parâmetro de ambiente `-E app|alb` para resolução automática da URL do Load Balancer.
- Exibe sumário estatístico completo ao finalizar (Ctrl+C ou `--count`).

### Exemplos de Execução:
```bash
# Monitorar o ALB do ambiente principal com requisições a cada 1 segundo:
./check-availability.sh -i 1

# Enviar exatamente 10 requisições de validação pontual:
./check-availability.sh -c 10
```

---

## 🔄 6. Fachada de Retrocompatibilidade (`deploy-ecs.sh`)

Mantém compatibilidade com comandos unificados e pipelines legados delegando de forma transparente:
```bash
./deploy-ecs.sh deploy [OPÇÕES]              # Encaminha para scripts/deploy.sh
./deploy-ecs.sh rollback [OPÇÕES]            # Encaminha para scripts/rollback.sh
./deploy-ecs.sh list [OPÇÕES]                # Encaminha para scripts/list-versions.sh
./deploy-ecs.sh check-availability [OPÇÕES]  # Encaminha para scripts/check-availability.sh
```

---

## 🧪 7. Suíte de Testes Automatizados (`test-security-checks.sh`)

Garante que nenhuma mutação acidental ocorra e valida rigorosamente todas as salvaguardas:

```bash
./test-security-checks.sh
```

### Cobertura dos 18 Testes:
1. Bloqueio por Conta AWS Não Autorizada no STS (`exit 1`).
2. Falha em `describe-task-definition` bloqueia antes de Docker Build/Push (`exit 1`).
3. Revisão 15 Real é consultada e propriedades (`placementConstraints`, secrets SSM, env) são integralmente preservadas.
4. Contêiner ausente na Task Definition base bloqueia antes de Build/Push (`exit 1`).
5. Ambiguidade de contêineres duplicados bloqueia antes de Build/Push (`exit 1`).
6. Família divergente bloqueia antes de Build/Push (`exit 1`).
7. Task Definition base com status `INACTIVE` bloqueia antes de Build/Push (`exit 1`).
8. Bloqueio rígido da revisão defeituosa `:16` (`exit 1`).
9. Rollout com `desiredCount=0` bloqueia homologação com erro (`exit 1`).
10. Disparo de ECS Deployment Circuit Breaker (`rolloutState=FAILED`) aciona diagnóstico read-only e sai com `exit 2`.
11. Dry-Run offline no ambiente ALB exibe mocks isolados sem vazar revisões do ambiente APP.
12. Execução direta do script especializado `list-versions.sh` em dry-run.
13. Execução direta do script especializado `rollback.sh` com bloqueio da `:16` e dry-run.
14. Execução direta do script especializado `deploy.sh` em modo dry-run.
15. Fachada de compatibilidade `deploy-ecs.sh` delegando com sucesso para `list`, `rollback` e `deploy`.
16. Falha persistente no Smoke Test dispara auto-rollback para a baseline de partida no serviço e sai com código `3`.
17. Smoke Test tolera falha transitória de warmup HTTP (ex: 502) com retentativa resiliente e conclui com código `0`.
18. Rollback dinâmico com baseline alternativa (ex: `:17`) não fica preso à `:15`, respeitando rigorosamente a versão ativa de partida.
