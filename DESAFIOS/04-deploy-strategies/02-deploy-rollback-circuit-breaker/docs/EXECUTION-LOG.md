# Diário de Execução Operacional — Desafio 02

> **Projeto:** BIA Cloud Lab — D2NS / Formação AWS<br>
> **Trilha:** `04-deploy-strategies` | **Desafio:** `02-deploy-rollback-circuit-breaker`<br>
> **Região:** `us-east-2` | **Perfil CLI:** `agy-aws-lab`<br>
> **Nota de Sanitização:** Identificadores como conta AWS e endpoints utilizam valores didáticos (`123456789012` e hostnames de exemplo) para conformidade pública.

---

## 📋 1. Visão Geral da Execução Forense

Este documento registra a sequência cronológica dos eventos, diagnósticos e validações empíricas executadas na nuvem AWS para homologação do **ECS Deployment Circuit Breaker** e das rotinas de **Rollback Automatizado**.

---

## ⏱️ 2. Linha do Tempo dos 5 Grandes Marcos

### Marco 1: Auditoria e Descoberta Inicial
* **Ações:** Execução de chamadas read-only no STS, ECS, ASG, RDS e ALB.
* **Diagnóstico Inicial:** O ambiente encontrava-se em repouso de computação ($0/h em EC2 e tarefas ECS). A política `deploymentCircuitBreaker` estava desativada no serviço `service-bia-cloud-app`.
* **Correção:** Habilitação do Circuit Breaker nativo via CLI:
  ```bash
  aws ecs update-service --cluster cluster-bia-app --service service-bia-cloud-app \
    --deployment-configuration "deploymentCircuitBreaker={enable=true,rollback=true}" \
    --profile agy-aws-lab --region us-east-2
  ```

### Marco 2: Ativação da Baseline Estável (Revisão 15)
* **Ações:** Ativação do ASG com 2 instâncias `t3.small` e publicação do serviço na Revisão `:15` (imagem `elasticache-v2`).
* **Validação:** A tarefa estabilizou como saudável no Target Group `tg-bia-app` (porta 8080) e respondeu `HTTP 200 OK` (`Bia 4.2.0`) no endpoint `/api/versao`.

### Marco 3: Injeção de Falha Deliberada (Revisão 16)
* **Ações:** Registro da Task Definition contaminada [`task-def-fail.example.json`](../templates/task-def-fail.example.json) com comando de parada imediata (`echo '[SIMULACAO] Falha critica' && exit 1`), gerando a Revisão `:16`.
* **Início do Rollout Defeituoso:** Atualização do serviço para a Revisão `:16` enquanto uma sonda de monitoramento HTTP em background realizava requisições a cada 2 segundos no ALB.

### Marco 4: Disparo do ECS Deployment Circuit Breaker
* **Comportamento Observado no Plano de Controle:**
  1. O ECS tentou subir a primeira tarefa da Revisão `:16`. O contêiner encerrou com código 1 (`STOPPED - Essential container in task exited`).
  2. O ECS agendou uma segunda e uma terceira tentativa consecutiva de subida. Ambas falharam com `exit 1`.
  3. Ao atingir o limiar de 3 falhas consecutivas ($\min(200, \max(3, \lceil 1 \times 0.5 \rceil)) = 3$), o ECS abortou o deployment.
  4. **Evento Registrado no CloudWatch / ECS:** `(service service-bia-cloud-app) deployment has failed: task-def-bia-cloud-app:16`.
  5. **Rollback Autônomo:** O plano de controle reverteu o deployment para a Revisão `:15` anterior e restaurou a tarefa estável sem necessidade de intervenção humana.

### Marco 5: Telemetria e Medição de Disponibilidade
* **Resultado Observado:** O monitor HTTP registrou **298 requisições consecutivas `HTTP 200 OK`** durante toda a janela de injeção de falha, detecção e reversão do Circuit Breaker.
* **Interpretação SRE:** Comprova que o ALB manteve o tráfego 100% roteado para a tarefa v1 saudável enquanto a v2 falhava. Não representa garantia de SLA permanente, mas atesta o comportamento de resiliência durante o teste monitorado.

---

## 🛠️ 3. Incidentes de Engenharia Solucionados

### Incidente 1: Conflito de Memória na Transição de Tarefas (`RESOURCE:MEMORY`)
* **Problema:** Ao testar o Rolling Update com apenas 1 nó `t3.small`, a subida da segunda tarefa travava com o evento `RESOURCE:MEMORY`.
* **Causa Raiz:** Cada task demanda 1024 MB. No pico da regra `maximumPercent = 200%`, são exigidos 2048 MB simultâneos. Uma instância `t3.small` fornece apenas 1913 MB de memória registrável para o ECS Agent (após reservas do SO e containerd).
* **Solução:** O Auto Scaling Group foi dimensionado para 2 instâncias `t3.small` distribuídas em AZs distintas (`us-east-2a` e `us-east-2b`), eliminando gargalos de RAM e limites de interfaces ENI em modo `awsvpc`.

### Incidente 2: Desacoplamento de Health Checks com o Banco RDS Desligado
* **Problema:** Risco de falsos positivos de indisponibilidade caso o health check dependesse do banco de dados relacional.
* **Causa Raiz & Solução:** A auditoria do código Express (`server.js`, `versao.js`) comprovou que o servidor HTTP sobe de forma assíncrona e a rota `/api/versao` responde diretamente em memória. O banco RDS permaneceu no estado `stopped`, economizando custos computacionais durante todo o Desafio 02.

---

## 🔒 4. Encerramento e Estado Atual dos Recursos

Após a homologação, o ambiente retornou ao standby de computação ($0.00/h em vCPU de EC2, tasks zeradas e RDS stopped). Recursos fixos como o ALB (~$0.0225/h) e armazenamento EBS do RDS (20 GB gp3 ~ $2.30/mês) foram mantidos provisionados para preservar os endpoints do laboratório.
