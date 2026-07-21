import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          // Per-test isolated KV namespace bound under the same name the
          // production worker uses. The pool resets between tests.
          kvNamespaces: ['SIGNALING_SESSIONS'],
          bindings: {
            // A deterministic key keeps HMACs reproducible across runs.
            WORKER_SECRET: 'test-worker-secret-do-not-use-in-prod',
            ICE_LONG_POLL_TIMEOUT_MS: '500',
            ICE_LONG_POLL_INTERVAL_MS: '50',
            RATE_LIMIT_PER_MINUTE: '30',
            SESSION_TTL_SECONDS: '600',
          },
        },
      },
    },
  },
});
