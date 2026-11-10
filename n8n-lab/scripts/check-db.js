let pg;
try {
  pg = require('pg');
} catch {
  pg = require('/usr/local/lib/node_modules/n8n/node_modules/.pnpm/pg@8.17.0/node_modules/pg');
}

const { Client } = pg;

const client = new Client({
  host: process.env.DB_POSTGRESDB_HOST || process.env.PGHOST,
  port: parseInt(process.env.DB_POSTGRESDB_PORT || process.env.PGPORT || '5432'),
  database: process.env.DB_POSTGRESDB_DATABASE || process.env.PGDATABASE || 'n8n',
  user: process.env.DB_POSTGRESDB_USER || process.env.PGUSER || 'postgres',
  password: process.env.DB_POSTGRESDB_PASSWORD || process.env.PGPASSWORD,
  ssl: { rejectUnauthorized: false }
});

async function main() {
  try {
    await client.connect();
    const res = await client.query('SELECT id, status, "createdAt", "startedAt", "stoppedAt" FROM execution_entity ORDER BY id DESC LIMIT 10;');
    console.log(JSON.stringify(res.rows, null, 2));
  } catch (err) {
    console.error('Erro DB:', err.message);
  } finally {
    await client.end();
  }
}

main();
