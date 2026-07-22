# Pulse — мастер-чеклист релиза в App Store и Google Play

Единая точка входа. Порядок сверху вниз — рабочий: сначала общие
предпосылки, затем Android-трек и iOS-трек (их можно вести параллельно),
в конце — сабмит. Пометки:

- **[код]** — уже сделано в репозитории (ветка `release/store-prep`);
- **[владелец]** — действие, которое может выполнить только владелец
  аккаунтов/устройств;
- **[документ]** — подробный runbook в `docs/release/`.

## 0. Предпосылки (однократно)

- [ ] **[владелец]** Аккаунт Apple Developer Program — $99/год
      (developer.apple.com → Enroll). Проверка занимает до 2 суток.
- [ ] **[владелец]** Аккаунт Google Play Console — $25 однократно
      (play.google.com/console). Новым личным аккаунтам Play требуется
      закрытое тестирование с ≥12 тестировщиками в течение 14 дней до
      выхода в production — заложите это в сроки.
- [ ] **[владелец]** Реальный e-mail поддержки. В приложении и сторах сейчас
      указан `support@pulse.app` — если домена нет, заведите адрес и
      замените строку `settingsSupportEmail` в `lib/l10n/app_*.arb`
      (+ `flutter gen-l10n`).
- [ ] **[владелец]** Опубликовать Privacy Policy и Terms по публичным URL —
      готовые файлы лежат в `docs/legal/` (варианты хостинга — в
      `docs/release/store_listings.md`, раздел «Хостинг юридических
      страниц»). Затем передавать URL в сборки через
      `--dart-define=LEGAL_PRIVACY_URL=… LEGAL_TERMS_URL=…`
      (дефолты: privacy → GitHub Pages этого репо, terms → стандартная
      EULA Apple).
- [ ] **[владелец]** Production-деплой signaling Worker — **[документ]**
      `signaling_production.md`. Результат: боевой
      `SIGNALING_BASE_URL`.
- [ ] **[владелец]** (Рекомендуется) TURN-релей для строгих NAT —
      **[документ]** `turn.md`. Без него P2P-неудачи уходят в relay-фолбэк
      через Worker (работает, но latency выше).
- [ ] Два физических устройства (Android+Android, iOS+iOS или смешанно) для
      сквозной проверки пейринга, транспортов и покупок.

## 1. Android-трек

- [x] **[код]** Release-подписание через `android/key.properties`,
      R8-правила, label `Pulse`, `targetSdk 35`, убраны неиспользуемые
      FGS-пермиссии.
- [ ] **[владелец]** Сгенерировать upload keystore и заполнить
      `android/key.properties` — **[документ]** `android_signing.md`.
- [ ] **[владелец]** Загрузить секреты в GitHub (Settings → Secrets →
      Actions): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `SIGNALING_BASE_URL`
      (+ опционально `TURN_URL`, `TURN_USER`, `TURN_CRED`).
- [ ] Собрать AAB: локально (`android_signing.md`) или тегом `v1.0.0`
      (workflow `release-android.yml` положит `app-release.aab` и
      `mapping.txt` в артефакты).
- [ ] **[владелец]** Создать приложение в Play Console и подписку —
      **[документ]** `play_console.md` (продукт `pulse_premium_monthly`,
      базовый план + intro offer «7 дней бесплатно», Data Safety, рейтинг).
- [ ] Залить AAB во внутреннее тестирование, прогнать смоук на двух
      устройствах: пейринг → BLE → LAN → WebRTC → покупка (тестовая карта)
      → restore. Первая сборка с R8 — проверить всё внимательно.
- [ ] Закрытое тестирование (требование Play для новых личных аккаунтов),
      затем production.

## 2. iOS-трек (нужен macOS + Xcode)

- [x] **[код]** PrivacyInfo.xcprivacy подключён к таргету Runner;
      `UIRequiresFullScreen=true`; экспортная криптография объявлена
      честно (`ITSAppUsesNonExemptEncryption=true`).
- [ ] **[владелец]** Создать App ID `io.pulseapp.pulse` и приложение в App
      Store Connect — **[документ]** `app_store_connect.md`.
- [ ] **[владелец]** Подписка `pulse_premium_monthly` + intro offer 7 дней
      бесплатно, цена (базовая ~149–199 ₽/мес — решение владельца),
      App Privacy (всё «Data Not Collected»), ответы по экспортной
      криптографии — **[документы]** `app_store_connect.md`,
      `export_compliance.md`.
- [ ] **[владелец]** Архив и выгрузка в TestFlight — **[документ]**
      `ios_release.md`.
- [ ] TestFlight-смоук на двух устройствах (sandbox-покупка, restore,
      ссылки Terms/Privacy с paywall открываются).

## 3. Ассеты и тексты сторов

- [ ] Тексты листингов RU/EN — готовые в **[документ]** `store_listings.md`
      (название, подзаголовок/короткое описание, полное описание,
      ключевые слова, release notes).
- [ ] Скриншоты — план сцен и размеров в **[документ]** `screenshots.md`.
      iPhone 6.7"/6.5" + iPad 13" (iPad обязателен, пока поддержан iPad),
      Android phone + 7"/10" планшеты (по желанию), feature graphic
      1024×500 для Play.
- [ ] Review notes для модерации обоих сторов — шаблон в **[документ]**
      `review_notes.md`. Ключевое: приложению нужно ДВА устройства —
      приложите демо-видео, иначе высок риск реджекта «app doesn't work».

## 4. Финальный сабмит

- [ ] Тег `v1.0.0` на коммите релиза (после мержа этой ветки).
- [ ] Play: production-релиз после закрытого теста.
- [ ] App Store: Submit for Review (ответы на вопросы экспортной
      криптографии — по `export_compliance.md`).
- [ ] После аппрува: смоук продовых сборок, мониторинг крешей в консолях
      (Play Vitals / Xcode Organizer — работают без внешней аналитики и не
      нарушают zero-data-collection).

## Известные ограничения v1 (осознанные, не блокеры)

- iOS: локальная квитанция не содержит даты истечения подписки —
  `expiresAt` уточняется тихим restore при запуске. Серверная валидация
  квитанций отложена (спека §9 это допускает).
- Локальный 7-дневный триал стартует при первом запуске независимо от
  стора; intro offer в сторах обязателен, чтобы CTA «Попробовать
  бесплатно» оставалась честной и после конца локального триала.
- `UIBackgroundModes: audio` должен реально использоваться активной
  сессией (спека §11); если на ревью спросят — см. review notes.
