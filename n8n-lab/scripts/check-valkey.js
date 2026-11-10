let Redis;
try {
  Redis = require('ioredis');
} catch {
  Redis = require('/usr/local/lib/node_modules/n8n/node_modules/.pnpm/ioredis@5.3.2/node_modules/ioredis');
}

const redis = new Redis({
  host: process.env.QUEUE_BULL_REDIS_HOST || process.env.REDIS_HOST,
  port: parseInt(process.env.QUEUE_BULL_REDIS_PORT || process.env.REDIS_PORT || '6379'),
  password: process.env.QUEUE_BULL_REDIS_PASSWORD || process.env.REDIS_PASSWORD,
  tls: (process.env.QUEUE_BULL_REDIS_TLS_ENABLED === 'true' || process.env.REDIS_TLS === 'true') ? { rejectUnauthorized: false } : undefined,
  connectTimeout: 5000,
  maxRetriesPerRequest: 1
});

async function main() {
  try {
    const keys = await redis.keys('*');
    const waitingJobs = await redis.lrange('bull:jobs:wait', 0, -1);
    const activeJobs = await redis.lrange('bull:jobs:active', 0, -1);
    const completedJobs = await redis.zrange('bull:jobs:completed', 0, -1);
    const idCount = await redis.get('bull:jobs:id');
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
    console.error('Erro Valkey:', err.message);
  } finally {
    redis.disconnect();
  }
}

main();
