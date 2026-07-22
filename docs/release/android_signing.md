# Android: release-подписание

Схема стандартная для Flutter: `android/key.properties` (не коммитится,
см. `.gitignore`) указывает на upload keystore; `android/app/build.gradle`
подхватывает его, если файл существует, иначе падает обратно на debug-ключи
(чтобы `flutter run --release` работал на машинах без секретов).

Play использует **Play App Signing**: вы подписываете AAB *upload*-ключом,
Google хранит и применяет ключ подписи приложения. Потеря upload-ключа не
фатальна (его можно сбросить через поддержку), но храните его как секрет.

## 1. Сгенерировать upload keystore (однократно)

```bash
keytool -genkey -v \
  -keystore ~/pulse-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Ответьте на вопросы (имя/организация — на ваше усмотрение), задайте два
пароля (keystore и ключа; можно одинаковые). Файл держите вне репозитория.

## 2. Локальная сборка

`android/key.properties` (создать руками, НЕ коммитить):

```properties
storePassword=<пароль keystore>
keyPassword=<пароль ключа>
keyAlias=upload
storeFile=/абсолютный/путь/к/pulse-upload-keystore.jks
```

Сборка:

```bash
flutter build appbundle --release \
  --dart-define=SIGNALING_BASE_URL=https://<prod-worker>.workers.dev \
  --dart-define=LEGAL_PRIVACY_URL=https://<ваш-хост>/legal/privacy.html \
  --dart-define=LEGAL_TERMS_URL=https://<ваш-хост>/legal/terms.html
  # + при наличии TURN: --dart-define=TURN_URL=... TURN_USER=... TURN_CRED=...
```

Результат: `build/app/outputs/bundle/release/app-release.aab`
(+ `build/app/outputs/mapping/release/mapping.txt` — загрузите в Play
Console → App bundle explorer → deobfuscation files, чтобы стектрейсы
крешей были читаемыми).

Проверка подписи:

```bash
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

## 3. Сборка в CI (workflow `release-android.yml`)

Секреты репозитория (Settings → Secrets and variables → Actions):

| Секрет | Значение |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ~/pulse-upload-keystore.jks` (macOS: `base64 -i ...`) |
| `ANDROID_KEYSTORE_PASSWORD` | пароль keystore |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | пароль ключа |
| `SIGNALING_BASE_URL` | боевой URL Worker'а |
| `TURN_URL` / `TURN_USER` / `TURN_CRED` | опционально |

Запуск: пуш тега `v*` (например `v1.0.0`) или вручную из вкладки Actions.
Артефакты: `pulse-release-aab`, `pulse-release-mapping`.

## Примечания

- Первая сборка идёт с включённым R8 (`minifyEnabled`) — keep-правила в
  `android/app/proguard-rules.pro`. Если на устройстве что-то падает с
  `ClassNotFoundException`/JNI-ошибками — присылайте стектрейс, правило
  добавляется одной строкой.
- `compileSdk`/`targetSdk` намеренно захардкожены (35). Play двигает
  требование каждый август — при апгрейде поднимайте сознательно вместе с
  прогоном на устройствах.
