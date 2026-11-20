/**
 * check-valkey.js — Diagnóstico de Conectividade com ElastiCache Valkey (BullMQ)
 *
 * Finalidade:
 * Valida a conectividade TCP/TLS e autenticação com o broker Valkey (compatível com Redis 7.2)
 * utilizado pela fila BullMQ do N8N, inspecionando contagens de jobs em espera, ativos e concluídos.
 *
 * Uso:
 * QUEUE_BULL_REDIS_HOST=<endpoint> QUEUE_BULL_REDIS_PASSWORD=<token> node check-valkey.js
 */

let Redis;
try {
  Redis = require('ioredis');
} catch {
  try {
    // Fallback para execução dentro do container oficial n8nio/n8n
    Redis = require('/usr/local/lib/node_modules/n8n/node_modules/.pnpm/ioredis@5.3.2/node_modules/ioredis');
  } catch {
    console.error('Erro: Pacote "ioredis" não encontrado. Instale com "npm install ioredis" ou execute dentro do container do N8N.');
    process.exit(1);
  }
}

// Validações defensivas de variáveis obrigatórias
const host = process.env.QUEUE_BULL_REDIS_HOST || process.env.REDIS_HOST;

if (!host) {
  console.error('Erro de configuração: Variável QUEUE_BULL_REDIS_HOST (ou REDIS_HOST) não informada.');
  process.exit(1);
}

const isTls = (process.env.QUEUE_BULL_REDIS_TLS === 'true' ||
               process.env.QUEUE_BULL_REDIS_TLS_ENABLED === 'true' ||
               process.env.REDIS_TLS === 'true');

const redis = new Redis({
  host: host,
  port: parseInt(process.env.QUEUE_BULL_REDIS_PORT || process.env.REDIS_PORT || '6379', 10),
  password: process.env.QUEUE_BULL_REDIS_PASSWORD || process.env.REDIS_PASSWORD || undefined,
  tls: isTls ? { rejectUnauthorized: false } : undefined,
  connectTimeout: parseInt(process.env.REDIS_CONNECTION_TIMEOUT_MS || '5000', 10),
  maxRetriesPerRequest: 1,
  lazyConnect: false
});

async function main() {
  try {
    console.log(`[INFO] Conectando ao ElastiCache Valkey em ${host} (TLS: ${isTls})...`);
    const ping = await redis.ping();
    console.log(`[OK] Resposta PING: ${ping}`);

    const keys = await redis.keys('*');
    const waitingJobs = await redis.lrange('bull:jobs:wait', 0, -1);
    const activeJobs = await redis.lrange('bull:jobs:active', 0, -1);
    const completedJobs = await redis.zrange('bull:jobs:completed', 0, -1);
    const idCount = await redis.get('bull:jobs:id');

    console.log('[OK] Estado do Message Broker BullMQ:');
    console.log(JSON.stringify({
      totalKeys: keys.length,
      keys: keys,
      waitingJobsCount: waitingJobs.length,
      waitingJobIds: waitingJobs,
      activeJobsCount: activeJobs.length,
      activeJobIds: activeJobs,
      completedJobsCount: completedJobs.length,
      completedJobIds: completedJobs,
      lastGeneratedJobId: idCount
    }, null, 2));
  } catch (err) {
    console.error('[ERRO] Falha no diagnóstico Valkey:', err.message);
    process.exitCode = 1;
  } finally {
    try {
      redis.disconnect();
    } catch {}
  }
}

main();
