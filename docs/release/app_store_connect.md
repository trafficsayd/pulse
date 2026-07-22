# App Store Connect: настройка приложения и подписки

Все шаги — в браузере на appstoreconnect.apple.com (нужен активный Apple
Developer Program).

## 1. Создать приложение

My Apps → «+» → New App:

- Platforms: **iOS**
- Name: **Pulse — тихая связь** (RU-витрина; EN-локализация ниже добавит
  «Pulse — quiet connection»). Имя должно быть свободно; если занято —
  варианты в `store_listings.md`.
- Primary Language: **Russian**
- Bundle ID: **io.pulseapp.pulse** (если нет в списке — Certificates,
  Identifiers & Profiles → Identifiers → «+» → App ID, включите капабилити
  In-App Purchase; Xcode с automatic signing создаст его и сам).
- SKU: `pulse-ios-1`

## 2. Подписка (Guideline 3.1.2 — самое проверяемое место)

Monetization → Subscriptions:

1. Create Subscription Group: reference name `Pulse Premium`.
2. В группе → Create Subscription:
   - Reference Name: `Pulse Premium Monthly`
   - **Product ID: `pulse_premium_monthly`** — ровно так, это захардкожено
     в `IapProductIds.premiumMonthly`.
   - Duration: **1 month**.
3. Price: базовая цена **149 ₽/мес** или ближайший тир к 150 ₽ (спека §9;
   Apple сам разложит по странам). Решение по цене — за владельцем.
4. **Introductory Offer** → Free trial → **7 days** (все страны). Без него
   кнопка «Попробовать бесплатно» на paywall станет обманом → реджект.
5. Localizations (RU + EN):
   - RU: Display Name «Pulse Premium», Description «Все режимы, безлимитный
     Sneak In, до 10 связей».
   - EN: «Pulse Premium», «All modes, unlimited Sneak In, up to 10
     connections».
6. Review Information → Screenshot: скриншот paywall-экрана (можно из
   симулятора, 1170×2532+). Обязателен для ревью подписки.
7. Статус подписки должен стать «Ready to Submit» — подписка сабмитится
   ВМЕСТЕ с первой версией приложения (отметьте её в разделе In-App
   Purchases and Subscriptions на странице версии).

## 3. App Privacy (nutrition labels)

App Privacy → Get Started:

- *Do you or your third-party partners collect data from this app?* →
  **No, we do not collect data from this app.**

Это честно: нет аккаунтов, аналитики, телеметрии; ключи и трафик не
покидают устройства (реле видит только шифртекст и случайные токены,
данные не сохраняются). Итог на витрине: **«Data Not Collected»**.

- Privacy Policy URL: ваш опубликованный
  `https://<хост>/legal/privacy.html`.

## 4. Страница версии 1.0.0

- Screenshots: iPhone 6.7" (обязательно) + iPad 13" (обязательно, пока
  поддерживается iPad) — план сцен в `screenshots.md`.
- Description / Keywords / Promotional Text: готовые тексты в
  `store_listings.md` (RU + EN локализации страницы).
- Support URL: страница репо/лендинг; Marketing URL — опционально.
- **App Review Information**: контакт + notes из `review_notes.md`
  (ключевое: два устройства, приложено демо-видео).
- Age Rating: анкета — везде «No» → итог 4+. Спека ориентирует на 13+,
  но контента 13+ по анкете Apple нет; можно добавить Age Rating 13+
  вручную опцией «Made for Kids» НЕ включать. Оставьте расчётный рейтинг.
- Pricing and Availability: цена приложения **Free**; страны — все, кроме
  Франции до подачи ANSSI-декларации (см. `export_compliance.md`).

## 5. Сабмит

- Билд из TestFlight → Add Build.
- Export Compliance: ответы из `export_compliance.md`.
- Submit for Review. Первый ответ обычно в течение 24–48 ч.

## Częste причины реджекта — уже закрыты кодом

| Риск | Статус |
| --- | --- |
| Битые ссылки Terms/Privacy на paywall | Починено (реальные URL) |
| Цена не из стора | Починено (ProductDetails.price) |
| Нет Restore Purchases | Была всегда |
| Privacy manifest отсутствует в бандле | Починено (Resources-фаза) |
| iPad-ориентации vs multitasking | Починено (UIRequiresFullScreen) |
| «Try free» без intro offer | Закрывается шагом 2.4 — не пропустите |
