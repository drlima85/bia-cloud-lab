# 🔄 Trilha: Estratégias de Deploy & Resiliência

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** Estratégias de Deploy & Resiliência<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Concluído e Documentado (4 Desafios Estruturados)<br>

Laboratórios dedicados a padrões de entrega contínua, mitigação de indisponibilidade e processos de recuperação e reversão de versões no Amazon ECS.

## 📚 Atribuição e Origem

- **Projeto:** BIA Cloud Lab — D2NS
- **Contexto Educacional:** Padrões de entrega e ciclo de vida de contêineres ensinados na **Formação AWS** (Henrylle Maia).
- **Implementações e Adaptações:** Desenvolvidas por **Danilo Lima — D2NS**.
- **Adaptações D2NS:** Modelagem matemática de dimensionamento para Rolling Update (min: 100%, max: 200%), templates de ECS Deployment Circuit Breaker autônomo, desacoplamento Blue/Green (manual via ALB e gerenciado via AWS CodeDeploy), governança consultiva assistida por IA (Amazon Bedrock) e scripts utilitários defensivos de deploy, rollback e monitoramento de disponibilidade.

---

## 🎯 Índice dos Desafios

| Desafio | Título | Estado | Foco Técnico |
|---|---|:---:|---|
| **01** | [01-rolling-update](01-rolling-update/README.md) | 🟡 Implementado / Documentado | Atualização gradual no ECS com capacidade mínima controlada (`minimumHealthyPercent` e `maximumPercent`). |
| **02** | [02-deploy-rollback-circuit-breaker](02-deploy-rollback-circuit-breaker/README.md) | 🟢 Homologado na Nuvem / Em Repouso | Reversão manual via CLI modular (`scripts/`) e automação nativa via ECS Deployment Circuit Breaker homologada na nuvem. |
| **03** | [03-blue-green](03-blue-green/README.md) | 🟡 Documentado & Modelado | Alternância controlada de tráfego entre ambientes de release e validação (manual via ALB e gerenciada via CodeDeploy). |
| **04** | [04-blue-green-ai](04-blue-green-ai/README.md) | 📐 Arquitetura Proposta | Governança consultiva assistida por Foundation Models (Amazon Bedrock), telemetria de ALB e Human-in-the-Loop. |

---

## 🛠️ Scripts e Memorial Técnico

- **[Scripts Utilitários](scripts/README.md):** Versões sanitizadas e defensivas de deploy, rollback e monitoramento contínuo de disponibilidade (`check-availability.sh`).
- **[Memorial Arquitetural](docs/architecture.md):** Análise comparativa completa de capacidade, topologias de rede, dimensionamento e gestão de segredos.
- **[Architecture Decision Records (ADRs)](docs/architecture-decisions.md):** 6 registros formais de decisões de design técnico (ADR 01 a 06).

---

## 📌 Diferenciação entre Objetivos e Evidências

- **Rolling Update:** Automação funcional codificada em [scripts/deploy-ecs.sh](scripts/deploy-ecs.sh) e histórico de execução registrado; a prova empírica formal de Zero Downtime mediante testes contínuos de carga sem perda de requisições permanece classificada como validação pendente.
- **Rollback & Circuit Breaker:** Homologado na nuvem com injeção de falha na Fase 2 com 100% de sucesso e Zero Downtime observado no ALB durante a janela monitorada (298 requisições consecutivas HTTP 200); suite de scripts especializada e defensiva em [`scripts/`](scripts/) validada com 18 testes automatizados; ambiente colocado em repouso controlado (custo de computação $0/h) com documentação de retomada em [`02-deploy-rollback-circuit-breaker/docs/HANDOFF.md`](02-deploy-rollback-circuit-breaker/docs/HANDOFF.md).
- **Blue/Green:** Experiência prática de alternância manual via ALB vivenciada em laboratórios guiados da formação; modelagem arquitetural com templates para abordagem manual (ALB) e gerenciada (CodeDeploy) documentada; automação de pipeline na nuvem classificada como evolução futura planejada.
- **Blue/Green AI:** Arquitetura conceitual proposta para tomada de decisão consultiva via agentes Foundation Models (Bedrock), estritamente em modo read-only e com supervisão humana mandatória.
