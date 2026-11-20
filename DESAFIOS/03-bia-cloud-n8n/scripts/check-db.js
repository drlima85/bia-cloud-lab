/**
 * check-db.js — Diagnóstico de Conectividade com PostgreSQL (N8N)
 *
 * Finalidade:
 * Valida a conectividade TCP/TLS e autenticação com o banco Amazon RDS PostgreSQL
 * utilizado pelo N8N, consultando as 10 últimas entradas da tabela execution_entity.
 *
 * Uso:
 * DB_POSTGRESDB_HOST=<endpoint> DB_POSTGRESDB_PASSWORD=<senha> node check-db.js
 */

let pg;
try {
  pg = require('pg');
} catch {
  try {
    // Fallback para execução dentro do container oficial n8nio/n8n
    pg = require('/usr/local/lib/node_modules/n8n/node_modules/.pnpm/pg@8.17.0/node_modules/pg');
  } catch {
    console.error('Erro: Pacote "pg" não encontrado. Instale com "npm install pg" ou execute dentro do container do N8N.');
    process.exit(1);
  }
}

const { Client } = pg;

// Validações defensivas de variáveis obrigatórias
const host = process.env.DB_POSTGRESDB_HOST || process.env.PGHOST;
const password = process.env.DB_POSTGRESDB_PASSWORD || process.env.PGPASSWORD;

if (!host) {
  console.error('Erro de configuração: Variável DB_POSTGRESDB_HOST (ou PGHOST) não informada.');
  process.exit(1);
}

if (!password) {
  console.error('Erro de configuração: Variável DB_POSTGRESDB_PASSWORD (ou PGPASSWORD) não informada.');
  process.exit(1);
}

const client = new Client({
  host: host,
  port: parseInt(process.env.DB_POSTGRESDB_PORT || process.env.PGPORT || '5432', 10),
  database: process.env.DB_POSTGRESDB_DATABASE || process.env.PGDATABASE || 'n8n',
  user: process.env.DB_POSTGRESDB_USER || process.env.PGUSER || 'postgres',
  password: password,
  ssl: process.env.DB_POSTGRESDB_SSL_ENABLED === 'false' ? false : {
    rejectUnauthorized: process.env.DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED === 'true'
  },
  connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT_MS || '5000', 10)
});

async function main() {
  try {
    console.log(`[INFO] Conectando ao PostgreSQL em ${host}...`);
    await client.connect();
    console.log('[OK] Conexão estabelecida com sucesso.');

    const res = await client.query('SELECT id, status, "createdAt", "startedAt", "stoppedAt" FROM execution_entity ORDER BY id DESC LIMIT 10;');
    console.log('[OK] Registros recentes da execution_entity:');
    console.log(JSON.stringify(res.rows, null, 2));
  } catch (err) {
    console.error('[ERRO] Falha no diagnóstico PostgreSQL:', err.message);
    process.exitCode = 1;
  } finally {
    try {
      await client.end();
    } catch {}
  }
}

main();
