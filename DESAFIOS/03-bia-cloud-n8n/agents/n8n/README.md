# 🤖 Agente Personalizado: `n8n` (Especialista AWS DevOps)

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** N8N na AWS (Plataforma de Automação & Workflows)<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** 📐 Especificação Consultiva Modelada<br>
> **Adaptações D2NS:** Modelagem de agente DevOps especializado em governança de menor privilégio IAM, controle de custos sem NAT Gateway, resiliência de filas com ElastiCache Valkey e testes controlados.

Especificação e documentação do agente especialista em **AWS DevOps para a plataforma N8N**, modelado para prover governança técnica, suporte operacional e planejamento arquitetural para os desafios da trilha [`03-bia-cloud-n8n`](../../README.md).

---

## 📚 Origem e Histórico

- **Projeto:** BIA Cloud Lab — D2NS
- **Origem Histórica:** Desenvolvido originalmente para a governança controlada das sessões práticas de implantação do N8N na AWS durante a **Formação AWS**, ministrada por **Henrylle Maia**.
- **Preservação do Histórico:** O arquivo operacional original permanece arquivado em [`n8n-lab/.agents/agents/agent.md`](../../../../n8n-lab/.agents/agents/agent.md) como registro factual da execução do Desafio 5.
- **Consolidação na Trilha:** Esta pasta formaliza a especificação arquitetural do agente, padronizada para o ecossistema público e sanitizada para replicação em laboratórios corporativos.

---

## 🧠 Papel e Escopo de Atuação

O agente `n8n` foi projetado para atuar como guardião técnico da infraestrutura de automação:

1. **Governança da Fase 1 (Single-Mode com Auto-Recovery):**
   - Garantir a operação em modo `bridge` com Dynamic Port Mapping no Amazon ECS, eliminando custos de NAT Gateway.
   - Avaliar a saúde de endpoints em `/healthz` e a recuperação automática de contêineres e instâncias EC2 pelo Auto Scaling Group.
2. **Governança da Fase 2 (Queue Mode Desacoplado):**
   - Apoiar na divisão funcional entre Tasks Main (UI e recepção de webhooks) e Tasks Workers (execução assíncrona).
   - Validar a conectividade criptografada (TLS) e autenticação com o **Amazon ElastiCache Valkey 7.2** operando como broker BullMQ.
3. **Gestão Orçamentária e Segurança:**
   - Impor aprovação humana mandatória antes de qualquer ação que modifique ou crie recursos na AWS.
   - Proibir expressamente o provisionamento inadvertido de componentes caros em contas de laboratório (ex.: NAT Gateways).
   - Assegurar que nenhum segredo seja gravado em texto claro, auditando a injeção via SSM Parameter Store.

---

## ⚙️ Relação com o Ecossistema de Agentes

> [!IMPORTANT]
> **Status de Ativação:** Este arquivo representa uma **especificação consultiva** mantida dentro da trilha `03-bia-cloud-n8n`.<br>
> Este agente **NÃO é carregado automaticamente pelo AGY** no ambiente raiz do projeto (`.agents/` ou `.kiro/`), servindo como documentação arquitetural e modelo reproduzível de governança.

### Instruções Consultivas para Ativação Futura (AGY)

Caso deseje ativar este agente no **Antigravity CLI (AGY)** para uma nova sessão de estudos:

1. Criar a pasta de destino em `.agents/agents/n8n/` na raiz do projeto:
   ```bash
   mkdir -p .agents/agents/n8n
   cp DESAFIOS/03-bia-cloud-n8n/agents/n8n/agent.md .agents/agents/n8n/
   ```
2. Configurar o perfil seguro `n8n-lab` no arquivo local `.agents/mcp_config.json` na raiz, conforme o modelo documentado na trilha.
3. O agente estará disponível no CLI sob a persona `n8n`.
