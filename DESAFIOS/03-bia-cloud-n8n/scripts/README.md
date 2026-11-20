# Scripts Utilitários de Diagnóstico — N8N na AWS

> **Projeto:** BIA Cloud Lab — D2NS<br>
> **Trilha:** N8N na AWS (Automação & Workflows)<br>
> **Referência educacional:** Formação AWS — Henrylle Maia<br>
> **Implementação e adaptações:** Danilo Lima — D2NS<br>
> **Status:** ✅ Validado Sintaticamente (Ambiente Desprovisionado — Histórico Homologado em 2026-11-09)<br>
> **Adaptações D2NS:** Sanitização e parametrização defensiva de scripts em Node.js (`check-db.js`, `check-valkey.js`) para diagnóstico seguro sem credenciais expostas.

Este diretório contém utilitários leves em Node.js desenvolvidos para validação rápida de conectividade e inspeção operacional da camada de dados (**Amazon RDS PostgreSQL**) e do message broker de fila (**Amazon ElastiCache Valkey**) da plataforma N8N.

> [!NOTE]
> **Status de Execução e Homologação:**<br>
> Os diagnósticos originais correspondentes foram executados e homologados na AWS durante a validação técnica do Desafio 6 em 2026-11-09.<br>
> As versões reorganizadas e sanitizadas disponibilizadas neste diretório **não foram executadas contra a nuvem AWS**, uma vez que a infraestrutura do laboratório foi integralmente desprovisionada (teardown controlado) após a homologação para evitar cobranças recorrentes.

---

## 1. Catálogo dos Scripts de Diagnóstico

| Script | Alvo do Diagnóstico | Finalidade Operacional |
|---|---|---|
| [`check-db.js`](check-db.js) | Amazon RDS PostgreSQL | Valida conectividade TCP e handshake SSL/TLS com o banco relacional, consultando os 10 últimos registros da tabela `execution_entity` (status, timestamps de início e fim). |
| [`check-valkey.js`](check-valkey.js) | Amazon ElastiCache Valkey | Valida conectividade TLS e autenticação via AUTH Token com o broker Valkey (Redis 7.2), inspecionando chaves do BullMQ (`bull:jobs:wait`, `bull:jobs:active`, `bull:jobs:completed`). |

---

## 2. Dependências Necessárias

Os scripts dependem dos drivers padrão de ecossistema Node.js:
* `pg` (v8.x): Cliente PostgreSQL para Node.js.
* `ioredis` (v5.x): Cliente Redis/Valkey robusto com suporte nativo a TLS e BullMQ.

### Opções de Execução do Runtime:
1. **Dentro do Container Oficial N8N (Recomendado):**
   A imagem Docker oficial (`n8nio/n8n:2.22.6`) já possui os pacotes `pg` e `ioredis` instalados globalmente no caminho de módulos do Node.js. Os scripts incluem detecção automática para esse ambiente.
2. **Ambiente Local / Bastion Host:**
   Caso executado em uma máquina de suporte (ex: bastion host na mesma VPC), instale as dependências com:
   ```bash
   npm install pg ioredis
   ```

---

## 3. Variáveis de Ambiente Suportadas

Os scripts leem a configuração diretamente de variáveis de ambiente, alinhadas aos nomes esperados pelo container do N8N:

### 3.1 PostgreSQL (`check-db.js`)

| Variável | Padrão | Descrição |
|---|---|---|
| `DB_POSTGRESDB_HOST` (ou `PGHOST`) | *Obrigatório* | Endpoint DNS privado da instância RDS PostgreSQL. |
| `DB_POSTGRESDB_PASSWORD` (ou `PGPASSWORD`) | *Obrigatório* | Senha master do banco (injetada com segurança via SSM). |
| `DB_POSTGRESDB_PORT` (ou `PGPORT`) | `5432` | Porta TCP do serviço PostgreSQL. |
| `DB_POSTGRESDB_DATABASE` (ou `PGDATABASE`) | `n8n` | Nome da base de dados utilizada pelo N8N. |
| `DB_POSTGRESDB_USER` (ou `PGUSER`) | `postgres` | Usuário administrador do banco de dados. |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` | Habilita criptografia em trânsito (SSL/TLS). |
| `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | `false` | Permite certificados da AWS sem validação estrita de CA no container. |
| `DB_CONNECTION_TIMEOUT_MS` | `5000` | Timeout máximo para estabelecimento da conexão (ms). |

### 3.2 ElastiCache Valkey (`check-valkey.js`)

| Variável | Padrão | Descrição |
|---|---|---|
| `QUEUE_BULL_REDIS_HOST` (ou `REDIS_HOST`) | *Obrigatório* | Endpoint primário do cluster ElastiCache Valkey. |
| `QUEUE_BULL_REDIS_PASSWORD` (ou `REDIS_PASSWORD`) | `undefined` | Token de autenticação (AUTH Token) do cluster Valkey. |
| `QUEUE_BULL_REDIS_PORT` (ou `REDIS_PORT`) | `6379` | Porta TCP do serviço Valkey / Redis. |
| `QUEUE_BULL_REDIS_TLS` | `true` | Ativa criptografia em trânsito (Transit Encryption). |
| `REDIS_CONNECTION_TIMEOUT_MS` | `5000` | Timeout para resposta do comando PING e handshake TLS (ms). |

---

## 4. Exemplos Seguros de Execução

> [!WARNING]
> Nunca execute os scripts passando senhas ou tokens diretamente em texto claro como argumentos de linha de comando (`ps aux` pode expor credenciais). Utilize arquivos `.env` protegidos com permissão `chmod 600` ou recupere segredos temporários via AWS CLI em variáveis voláteis de sessão.

### 4.1 Execução no Container ECS via ECS Exec (Recomendado)
```bash
# Acessar a task do N8N interativamente sem abrir portas no host
aws ecs execute-command \
  --cluster cluster-n8n-d2n \
  --task <TASK_ID> \
  --container n8n-main \
  --interactive \
  --command "/bin/sh"

# Dentro do container (onde as variáveis já estão injetadas via SSM):
node /opt/scripts/check-db.js
node /opt/scripts/check-valkey.js
```

### 4.2 Execução em Host de Suporte (Bastion na VPC)
```bash
# Exportar variáveis a partir de parâmetros SSM sem texto claro
export DB_POSTGRESDB_HOST="n8n.exemplo.us-east-2.rds.amazonaws.com"
export DB_POSTGRESDB_PASSWORD=$(aws ssm get-parameter --name "/n8n/db_password" --with-decryption --query "Parameter.Value" --output text)

node check-db.js

export QUEUE_BULL_REDIS_HOST="master.n8n-valkey.exemplo.use2.cache.amazonaws.com"
export QUEUE_BULL_REDIS_PASSWORD=$(aws ssm get-parameter --name "/n8n/valkey_token" --with-decryption --query "Parameter.Value" --output text)
export QUEUE_BULL_REDIS_TLS="true"

node check-valkey.js
```

---

## 5. Resultados Esperados

### 5.1 Saída Típica do `check-db.js`
```json
[INFO] Conectando ao PostgreSQL em n8n.exemplo.us-east-2.rds.amazonaws.com...
[OK] Conexão estabelecida com sucesso.
[OK] Registros recentes da execution_entity:
[
  {
    "id": 14,
    "status": "success",
    "createdAt": "2026-11-09T23:45:10.123Z",
    "startedAt": "2026-11-09T23:45:10.456Z",
    "stoppedAt": "2026-11-09T23:45:12.789Z"
  }
]
```

### 5.2 Saída Típica do `check-valkey.js`
```json
[INFO] Conectando ao ElastiCache Valkey em master.n8n-valkey.exemplo.use2.cache.amazonaws.com (TLS: true)...
[OK] Resposta PING: PONG
[OK] Estado do Message Broker BullMQ:
{
  "totalKeys": 5,
  "keys": [
    "bull:jobs:id",
    "bull:jobs:completed",
    "bull:jobs:wait"
  ],
  "waitingJobsCount": 0,
  "waitingJobIds": [],
  "activeJobsCount": 0,
  "activeJobIds": [],
  "completedJobsCount": 14,
  "completedJobIds": ["1", "2", "3"],
  "lastGeneratedJobId": "14"
}
```

---

## 6. Limitações dos Diagnósticos

1. **Escopo Somente Leitura:** Os scripts executam apenas consultas de inspeção (`SELECT` e comandos Redis `KEYS`, `LRANGE`, `ZRANGE`). Eles não realizam mutação de schemas, inserções ou deleções de chaves.
2. **Dependência de Rota na VPC:** Os recursos RDS e Valkey operam em sub-redes privadas ou sem IP público. A execução fora da VPC (ex: máquina local externa) falhará por timeout de conexão a menos que haja VPN ou túnel SSM / Bastion ativo.
3. **Comando `KEYS *` em Produção de Alta Escala:** Em instâncias Valkey/Redis com milhões de chaves ativas, o comando `KEYS *` pode causar latência momentânea de CPU. Em clusters corporativos de altíssima escala, substitua por `SCAN`.
