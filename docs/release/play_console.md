# Google Play Console: настройка приложения и подписки

Все шаги — на play.google.com/console.

> Важно для новых **личных** аккаунтов Play (после ноября 2023): перед
> production обязательно закрытое тестирование с минимум 12 тестировщиками,
> непрерывно 14 дней. Планируйте релиз с этим лагом.

## 1. Создать приложение

All apps → Create app:

- Name: **Pulse — тихая связь** (варианты в `store_listings.md`)
- Default language: **Russian (ru-RU)**
- App or game: App; Free or paid: **Free** (с покупками внутри)
- Декларации: принять.

## 2. Initial setup (Dashboard → Set up your app)

- **Privacy policy**: URL опубликованной
  `https://<хост>/legal/privacy.html`.
- **App access**: «All functionality is available without special access» —
  НО добавьте Instructions: полный функционал требует второго устройства;
  приложено демо-видео (см. `review_notes.md`).
- **Ads**: No ads.
- **Content rating**: анкета IARC → категория «Social/Communication»;
  вопросы (насилие, секс, азарт...) — везде No; «общаются ли пользователи»
  — Yes (контролируемое: только доверенные пары, без публичного контента).
  Итог обычно 3+/E; из-за коммуникации может быть выше — это нормально.
- **Target audience**: 13+ (спека §2). НЕ выбирайте «apps for children».
- **News app**: No.
- **Data safety** (важнейшая форма):
  - Does your app collect or share any of the required user data types? →
    **No**.
  - Обоснование, если ревью спросит: нет аккаунтов и серверного хранения;
    ключи в EncryptedSharedPreferences локально; реле передаёт только
    E2E-шифртекст эфемерно, без логирования содержимого; разрешения BLE
    объявлены с `neverForLocation`, координаты не считываются.
  - Security practices: «Data is encrypted in transit» → Yes.
  - Итог на витрине: **«No data collected»**.
- **Government apps / Financial features**: No.

## 3. Подписка

Monetize → Products → Subscriptions → Create subscription:

- **Product ID: `pulse_premium_monthly`** (ровно так — захардкожено в
  приложении). Name: «Pulse Premium».
- Base plan: id `monthly-autorenew`, Auto-renewing, период 1 месяц,
  цена **150 ₽** (по остальным странам Play конвертирует сам; поправьте
  ключевые рынки руками при желании).
- **Offer** к базовому плану: id `trial7`, eligibility «Never had this
  subscription», фаза Free trial **7 дней**. Это пара к intro offer в
  App Store — без неё CTA «Попробовать бесплатно» нечестна.
- Активируйте продукт, базовый план и оффер.

> Продукты подписки становятся доступны приложению только после того, как
> AAB с `com.android.billingclient` залит хотя бы во внутренний трек.
> Порядок: залить AAB → создать подписку → проверить paywall.

## 4. Внутреннее тестирование

1. Testing → Internal testing → Create release → загрузите
   `app-release.aab` (из CI-артефактов или локальной сборки) + в App
   bundle explorer → загрузить `mapping.txt` (deobfuscation).
2. Testers: список e-mail (оба ваших устройства).
3. License testing (Settings → License testing): добавьте свои аккаунты —
   покупки станут тестовыми (без списаний, ускоренное продление:
   1 месяц ≈ 5 минут — удобно проверять истечение).
4. Смоук на двух устройствах: пейринг, транспорты, покупка (paywall должен
   показать цену из Play, sheet — «7 дней бесплатно»), restore, Sneak In,
   фоновый режим.

## 5. Production

- Закрытое тестирование 14 дней / 12+ тестировщиков (для новых личных
  аккаунтов) → Apply for production.
- Store listing: тексты из `store_listings.md`, скриншоты из
  `screenshots.md`, feature graphic 1024×500.
- Countries: все (Play не требует французской декларации — это специфика
  Apple; юридически self-classification из `export_compliance.md`
  покрывает и Google Play, США).
- Roll out поэтапно (20% → 100%) — первая R8-сборка, наблюдайте Android
  Vitals.
