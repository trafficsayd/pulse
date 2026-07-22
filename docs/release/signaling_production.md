# Signaling Worker: production-деплой

Worker (`signaling/`) брокерит SDP/ICE для WebRTC и служит шифрованным
релеем-фолбэком. Содержимого сообщений он не видит (E2E), хранит только
эфемерные сессии в KV с TTL.

> ℹ️ `account_id` в `wrangler.toml` уже вписан
> (`75377a196e8fd601606b3fcf2a458356`) — подтверждён через API вашего
> подключённого аккаунта Cloudflare. Осталось создать KV и задеплоить.
>
> Почему это делается руками, а не агентом: OAuth-подключение Cloudflare к
> Hyperagent выдаёт токен **только на чтение** (проверено — создание KV,
> деплой Worker и регистрация workers.dev-поддомена возвращают
> «Authentication error»). Первый деплой всё равно требует интерактивной
> регистрации workers.dev-поддомена, что делается только в браузере. У
> `wrangler login` — свой OAuth с полными правами, поэтому команды ниже
> отработают штатно.

## 1. Однократная настройка Cloudflare

```bash
cd signaling
npm ci
npx wrangler login                     # браузерная авторизация (полные права)
```

`account_id` уже проставлен. Создайте KV-неймспейсы и подставьте id в
`signaling/wrangler.toml` (в блок `[[kv_namespaces]]` вместо
`REPLACE_ME_KV_NAMESPACE_ID` / `REPLACE_ME_KV_NAMESPACE_PREVIEW_ID`):

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
