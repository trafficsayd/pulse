# iOS: сборка и выгрузка в App Store

Требуется macOS с Xcode 15+. Подписание — автоматическое (Xcode managed),
отдельные сертификаты руками создавать не нужно.

## 0. Однократная подготовка

1. Xcode → Settings → Accounts → добавьте Apple ID команды разработчика.
2. App Store Connect: создайте приложение (см. `app_store_connect.md`) —
   App ID `io.pulseapp.pulse` регистрируется там же или автоматически
   Xcode'ом при первом подписании.
3. В Xcode откройте `ios/Runner.xcworkspace` (не `.xcodeproj`!), таргет
   Runner → Signing & Capabilities → Team = ваша команда,
   «Automatically manage signing» = on. Bundle Identifier уже
   `io.pulseapp.pulse`.

## 1. Сборка и выгрузка

```bash
flutter pub get

flutter build ipa --release \
  --dart-define=SIGNALING_BASE_URL=https://<prod-worker>.workers.dev \
  --dart-define=LEGAL_PRIVACY_URL=https://<ваш-хост>/legal/privacy.html \
  --dart-define=LEGAL_TERMS_URL=https://<ваш-хост>/legal/terms.html
  # + при наличии TURN: --dart-define=TURN_URL=... TURN_USER=... TURN_CRED=...
```

Результат — `build/ios/archive/Runner.xcarchive` и
`build/ios/ipa/pulse.ipa`. Выгрузка (любой вариант):

- **Xcode:** Window → Organizer → выбрать архив → Distribute App →
  App Store Connect → Upload;
- **CLI:** `xcrun altool` устарел — используйте
  `xcrun notarytool`-эпоху: `Transporter.app` из Mac App Store, либо
  `xcrun iTMSTransporter`, либо просто Organizer.

## 2. Что проверить в архиве ДО выгрузки

- Organizer → архив → правой кнопкой → Show in Finder → Show Package
  Contents → `Products/Applications/Runner.app` — внутри должен лежать
  **`PrivacyInfo.xcprivacy`** (мы зарегистрировали его в Resources-фазе;
  если Xcode после апгрейда «потерял» файл — Runner → Build Phases →
  Copy Bundle Resources → добавить заново).
- Version/Build берутся из `pubspec.yaml` (`1.0.0+1` → 1.0.0 / 1).

## 3. TestFlight

1. После выгрузки билд появляется в App Store Connect → TestFlight
   (обработка 10–30 мин).
2. Вопрос про экспортную криптографию при первом билде: отвечайте по
   `export_compliance.md` (коротко: «использует стандартные алгоритмы»).
3. Internal testing: добавьте себя + второго тестировщика (нужно два
   устройства). Sandbox-покупки в TestFlight не списывают деньги.

## Смоук-чеклист TestFlight (два устройства)

- [ ] Пейринг по 6-значному коду, SAS совпадает, связь сохранена.
- [ ] Транспорты: рядом (BLE) → одна Wi-Fi сеть (LAN) → разные сети
      (WebRTC/relay; индикатор жёлтый).
- [ ] Paywall: цена подтянулась из стора (не «150 ₽ / месяц» из фолбэка,
      а локализованная цена App Store); «Попробовать бесплатно» → sandbox
      sheet с «7 дней бесплатно»; Restore purchases; ссылки Terms/Privacy
      открываются.
- [ ] Sneak In между устройствами, квота триала соблюдается.
- [ ] Фон: свернуть приложение — BLE-связь и Sneak In живы.

## CI-вариант (опционально, позже)

GitHub Actions умеет собирать iOS на `macos-latest` (минуты дороже x10).
Понадобится экспорт p12-сертификата + provisioning profile в секреты или
fastlane match. Для v1 ручной Organizer-путь быстрее; вернёмся к
автоматизации после первого релиза.
