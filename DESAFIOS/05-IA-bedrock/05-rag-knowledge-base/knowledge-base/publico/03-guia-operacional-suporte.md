# BIA Cloud Lab — Guia Operacional, Suporte e Resolução de Problemas

> [!NOTE]
> Este documento contém informações fictícias e simplificadas para demonstração de Retrieval-Augmented Generation (RAG). Os exemplos de arquitetura, modelos de dados e endpoints não representam necessariamente a implementação real da aplicação BIA Cloud Lab.

## 1. Operação em Amazon ECS (Fargate)

Os serviços do BIA Cloud Lab rodam como tarefas ECS sob o modo de lançamento Fargate, eliminando o gerenciamento manual de instâncias EC2.

### 1.1 Verificação de Saúde (Health Checks)
- **Endpoint:** O ALB realiza checagens HTTP no caminho `/api/versao` a cada 30 segundos.
- **Critério de Sucesso:** Código de resposta HTTP `200 OK`.
- **Descarte de Instância:** Duas falhas consecutivas marcam a tarefa como não saudável, disparando a inicialização de uma nova tarefa substituta.

### 1.2 Logs e Métricas
- Todos os contêineres enviam logs diretamente para o **Amazon CloudWatch Logs** sob o grupo `/ecs/bia-backend` e `/ecs/bia-frontend`.
- Métricas chave monitoradas:
  - `CPUUtilization` (alerta se > 80% por 5 minutos).
  - `MemoryUtilization` (alerta se > 85% por 5 minutos).
  - `HTTPCode_Target_5XX_Count` (alerta se > 5 ocorrências por minuto).

---

## 2. Diagnóstico e Resolução de Problemas Frequentes

### 2.1 Erro `ECONNREFUSED` ao Conectar no PostgreSQL
- **Causa Comum:** Security Group do RDS não autoriza tráfego na porta 5432 originado da Security Group da task ECS.
- **Ação:** Verificar as regras de entrada (Inbound Rules) do Security Group do RDS e garantir que a origem seja o Security Group do backend, e não um IP estático.

### 2.2 Excesso de Conexões no Banco de Dados (`max_connections`)
- **Causa Comum:** Pool de conexões do Node.js mal dimensionado para a quantidade de tasks em execução simultânea.
- **Ação:** Configurar `max: 10` no pool do `pg` ou utilizar o **Amazon RDS Proxy** para multiplexação e compartilhamento eficiente de conexões.

### 2.3 Exceções no Amazon Bedrock (`ThrottlingException`)
- **Causa Comum:** Limite de requisições por minuto (RPM) ou tokens por minuto (TPM) da conta atingido na região `us-east-1`.
- **Ação:**
  - Implementar retentativa com recuo exponencial (Exponential Backoff with Jitter), recurso nativo do AWS SDK v3.
  - Utilizar modelos com menor consumo de cota para tarefas simples (ex.: Claude 3.5 Haiku).
  - Em ambientes de produção, solicitar aumento de cota de serviço (Service Quotas) para o Bedrock.

---

## 3. Procedimento de Atualização da Base RAG (Knowledge Base)

1. Faça upload dos novos documentos Markdown para o bucket S3 de dados do Knowledge Base.
2. Inicie a sincronização do Data Source no console Bedrock ou via AWS CLI:
   ```bash
   aws bedrock-agent start-ingestion-job \
     --knowledge-base-id "$KB_ID" \
     --data-source-id "$DATA_SOURCE_ID" \
     --region us-east-1
   ```
3. Acompanhe o status da sincronização até `COMPLETE` antes de executar os scripts RAG (`v7-rag-danilo.mjs`, `v8-rag-managed-danilo.mjs`).
