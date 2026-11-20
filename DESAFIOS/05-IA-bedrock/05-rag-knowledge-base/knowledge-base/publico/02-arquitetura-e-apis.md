# BIA Cloud Lab — Especificação Técnica de APIs e Banco de Dados

> [!NOTE]
> Este documento contém informações fictícias e simplificadas para demonstração de Retrieval-Augmented Generation (RAG). Os exemplos de arquitetura, modelos de dados e endpoints não representam necessariamente a implementação real da aplicação BIA Cloud Lab.

## 1. Endpoints da API REST de Tarefas

A API da BIA expõe endpoints sob o prefixo `/api/tarefas` para gerenciamento completo do ciclo de vida das tarefas.

### 1.1 `GET /api/tarefas`
- **Descrição:** Lista todas as tarefas cadastradas, com suporte a paginação e filtros.
- **Parâmetros de Consulta (Query Params):**
  - `status` (opcional): Filtra por status (`pendente`, `em_andamento`, `concluida`).
  - `prioridade` (opcional): Filtra por nível (`baixa`, `media`, `alta`, `critica`).
  - `limite` (padrão: 50): Quantidade máxima de registros retornados.
- **Exemplo de Resposta (200 OK):**
  ```json
  [
    {
      "id": 101,
      "titulo": "Configurar alarmes no CloudWatch",
      "descricao": "Criar alarme para utilização de CPU acima de 80% no ECS",
      "prioridade": "alta",
      "status": "em_andamento",
      "data_prazo": "2026-12-01T23:59:59Z",
      "flag_importante": true,
      "criado_em": "2026-11-15T10:00:00Z"
    }
  ]
  ```

### 1.2 `POST /api/tarefas`
- **Descrição:** Cria uma nova tarefa no sistema.
- **Payload Obrigatório:**
  ```json
  {
    "titulo": "Implementar ingestão RAG no S3",
    "descricao": "Enviar documentos para o bucket do Knowledge Base",
    "prioridade": "media"
  }
  ```
- **Código de Retorno:** `201 Created` com o objeto persistido e ID gerado.

### 1.3 `PUT /api/tarefas/:id`
- **Descrição:** Atualiza os dados de uma tarefa existente.
- **Código de Retorno:** `200 OK` em caso de sucesso ou `404 Not Found` caso o ID não exista.

### 1.4 `DELETE /api/tarefas/:id`
- **Descrição:** Remove logicamente ou fisicamente uma tarefa pelo ID.
- **Código de Retorno:** `204 No Content`.

### 1.5 `GET /api/versao`
- **Descrição:** Health check básico e verificação de versão da aplicação.
- **Exemplo de Resposta:** `{"versao": "2.1.0", "ambiente": "producao", "status": "operacional"}`.

---

## 2. Esquema do Banco de Dados PostgreSQL

A tabela principal de tarefas possui a seguinte DDL de referência:

```sql
CREATE TABLE IF NOT EXISTS tarefas (
    id SERIAL PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    descricao TEXT,
    prioridade VARCHAR(20) DEFAULT 'media' CHECK (prioridade IN ('baixa', 'media', 'alta', 'critica')),
    status VARCHAR(20) DEFAULT 'pendente' CHECK (status IN ('pendente', 'em_andamento', 'concluida')),
    data_prazo TIMESTAMP WITH TIME ZONE,
    flag_importante BOOLEAN DEFAULT FALSE,
    criado_em TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tarefas_status ON tarefas(status);
CREATE INDEX idx_tarefas_prioridade ON tarefas(prioridade);
```

---

## 3. Estratégia de Caching com Valkey / Redis

Para reduzir a latência de leitura e evitar consultas repetitivas ao banco RDS:
1. **Padrão Cache-Aside:**
   - Na leitura de `/api/tarefas`, o backend consulta a chave `cache:tarefas:todas`.
   - Se presente (cache hit), retorna diretamente em menos de 5ms.
   - Se ausente (cache miss), executa a query no PostgreSQL e armazena o resultado com TTL de 300 segundos (5 minutos).
2. **Invalidação Proativa:**
   - Qualquer operação de `POST`, `PUT` ou `DELETE` invalida imediatamente a chave `cache:tarefas:todas`.
