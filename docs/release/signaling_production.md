# Signaling Worker: production-деплой

Worker (`signaling/`) брокерит SDP/ICE для WebRTC и служит шифрованным
релеем-фолбэком. Содержимого сообщений он не видит (E2E), хранит только
эфемерные сессии в KV с TTL.

## 1. Однократная настройка Cloudflare

```bash
cd signaling
npm ci
npx wrangler login                     # браузерная авторизация
npx wrangler whoami                    # покажет account_id
```

В `signaling/wrangler.toml` замените:

- `account_id = "REPLACE_ME_ACCOUNT_ID"` → ваш account id;
- создайте KV и подставьте id:

```bash
npx wrangler kv namespace create SIGNALING_SESSIONS
npx wrangler kv namespace create SIGNALING_SESSIONS --preview
```

## 2. Секрет и деплой

```bash
# HMAC-ключ для подписи сессионных токенов — сгенерируйте стойкий:
openssl rand -base64 32 | npx wrangler secret put WORKER_SECRET

npx wrangler deploy
```

Итоговый URL: `https://pulse-signaling.<ваш-суффикс>.workers.dev` — это и
есть production `SIGNALING_BASE_URL`:

- локальные сборки: `--dart-define=SIGNALING_BASE_URL=...`;
- CI: секрет `SIGNALING_BASE_URL` в GitHub Actions.

⚠️ Дефолт в коде — `https://pulse-signaling.example.workers.dev`
(нерабочая заглушка). Release-сборка без правильного dart-define соберётся,
но интернет-тир работать не будет. CI-workflow специально падает, если
секрет не задан.

## 3. Рекомендации

- **Кастомный домен** (опционально): Workers → Triggers → Custom Domains,
  например `signal.<ваш-домен>`. Плюс: URL переживёт смену
  workers.dev-суффикса.
- **Лимиты free-тарифа**: 100k запросов/день. Long-poll ICE экономный
  (интервалы в `wrangler.toml`); для старта хватает с запасом, дальше —
  Workers Paid ($5/мес).
- **Мониторинг**: Workers → Observability (логи уже включены в
  `wrangler.toml`; содержимое сообщений в логи не попадает — проверено
  кодом, токены не логируются).
- **Смена WORKER_SECRET** инвалидирует активные сессии (клиенты просто
  пересоздадут их) — безопасно делать в любой момент.
