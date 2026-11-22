# Documento de Transição Técnica (HANDOFF) — Desafio 02

> **Projeto:** BIA Cloud Lab — D2NS / Formação AWS<br>
> **Trilha:** `04-deploy-strategies` | **Desafio:** `02-deploy-rollback-circuit-breaker`<br>
> **Estado dos Recursos:** Standby de Computação (0 instâncias EC2, 0 tasks ECS, RDS stopped)<br>
> **Nota de Sanitização:** Identificadores como conta AWS e endpoints de banco utilizam dados didáticos para conformidade pública.

---

## 🎯 1. Resumo Executivo da Arquitetura Entregue

O Desafio 02 implementou e homologou na nuvem AWS as estratégias de resiliência e auto-recuperação contínua no Amazon ECS:

* **Serviço Alvo:** `service-bia-cloud-app` (Cluster `cluster-bia-app`, launchType `EC2`, modo de rede `awsvpc`).
* **Estratégia de Rollout:** Rolling Update com `minimumHealthyPercent = 100%` e `maximumPercent = 200%` (garante capacidade total ininterrupta durante releases).
* **Auto-Recuperação Nativa:** Configuração `deploymentCircuitBreaker: { enable: true, rollback: true }`.
* **Roteamento e Health Checks:** Application Load Balancer (`bia-cloud-alb`) com Target Group `tg-bia-app` (porta 8080) e health check de aplicação em `/api/versao`.

---

## 🧪 2. Evidências Empíricas Consolidadas

A homologação na nuvem real (registrada em detalhes no [EXECUTION-LOG.md](EXECUTION-LOG.md)) comprovou:

1. **Auto-Rollback do ECS Deployment Circuit Breaker:**
   - Injeção controlada de falha deliberada na Revisão `:16` (comando com `exit 1`).
   - O control plane do ECS detectou o limiar de falhas consecutivas ($\min(200, \max(3, \lceil 1 \times 0.5 \rceil)) = 3$ tasks com falha).
   - O evento `rolloutState: FAILED` foi emitido e o ECS reverteu autonomamente o serviço para a Revisão `:15` estável sem intervenção humana.
2. **Disponibilidade Observada no ALB:**
   - A sonda de telemetria contínua registrou **298 respostas consecutivas `HTTP 200 OK`** durante toda a janela de injeção de falha e reversão.
   - *Nota de Engenharia:* Esse resultado comprova a eficácia do isolamento de tráfego do ALB durante o teste monitorado, sem constituir garantia de SLA absoluto ou permanente.
3. **Suíte Automatizada de Segurança:**
   - 18 testes automatizados de unidade e integração aprovados com 100% de sucesso em [`test-security-checks.sh`](../../scripts/test-security-checks.sh).

---

## 💰 3. Estado de Standby e Custos AWS Estimados

Para manter o laboratório em repouso sem gerar custos de computação desnecessários, o ambiente foi configurado conforme a tabela abaixo:

| Recurso | Estado Operacional | Custo Estimado | Observações Técnicas |
|---|:---:|:---:|---|
| **Auto Scaling Group** | `Desired: 0` | **$0.00/h** | Zero instâncias EC2 `t3.small` ativas no cluster. |
| **Serviço ECS** | `Desired: 0` | **$0.00/h** | Zero tarefas ativas no cluster. |
| **Amazon RDS (`bia-cloud`)** | `stopped` | **$0.00/h** (computação) | Cobrança de vCPU e memória da instância `db.t3.micro` suspensa. |
| **Armazenamento EBS RDS** | Alocado | **~$2.30/mês** | O volume `gp3` de 20 GB continua cobrado pela AWS enquanto a instância existir. |
| **Alerta de Auto-Restart RDS** | Mecanismo AWS | Atenção | A AWS religa automaticamente instâncias RDS paradas após 7 dias. Requer comando `stop` periódico. |
| **Application Load Balancer** | Provisionado | **~$0.0225/h** (~$16.20/mês) | Taxa básica fixa do balanceador para manter endpoints e regras ativas. |
| **Amazon ECR** | Repositório | **~$0.10/GB-mês** | Armazenamento das imagens estáveis (`elasticache-v2`, `rolling-purple-v1`). |

---

## 🚀 4. Continuidade Operacional

Para religar o ambiente e executar novos deploys ou testes na AWS real, consulte o guia passo a passo em [PRE-DEPLOY-CHECKLIST.md](PRE-DEPLOY-CHECKLIST.md).
