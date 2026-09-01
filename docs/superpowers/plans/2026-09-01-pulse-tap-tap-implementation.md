# Pulse «Тук-Тук» — план реализации

**Спецификация:** `docs/superpowers/specs/2026-09-01-pulse-tap-tap-design.md`  
**Цель:** заменить простое событие `tap` на живой, надёжный и совместимый Touch/Haptic Engine, сохранив мгновенный сценарий «я здесь».

## Этап 1. Чистая модель касания и серии

**Файлы:**

- создать `lib/features/modes/application/tap_tap/knock_models.dart`;
- создать `lib/features/modes/application/tap_tap/touch_character_normalizer.dart`;
- создать `lib/features/modes/application/tap_tap/knock_series_controller.dart`;
- создать `test/modes/application/tap_tap/touch_character_normalizer_test.dart`;
- создать `test/modes/application/tap_tap/knock_series_controller_test.dart`.

**Работа:**

- определить immutable-модели `KnockCharacter`, `KnockHit`, `KnockSeries`;
- нормализовать координаты, duration, contact size и optional pressure;
- вычислять `soft/clear/deep` и confidence без обещания физической силы;
- группировать hits по окну 900 мс, лимиту 16 hits и 12 секунд;
- вынести clock/ID generation для детерминированных тестов.

**Проверка:** unit-тесты границ, pressure fallback, лимитов и relative offsets.

## Этап 2. Versioned knock-протокол и legacy совместимость

**Файлы:**

- создать `lib/features/modes/application/tap_tap/knock_protocol.dart`;
- изменить `lib/features/modes/application/mode_registry.dart`;
- обновить документацию типов в `lib/features/session/application/mode_event.dart`;
- создать `test/modes/application/tap_tap/knock_protocol_test.dart`;
- изменить `test/modes/application/mode_event_mapping_test.dart`.

**Работа:**

- добавить `knock_begin`, `knock_hit`, `knock_end`, `knock_reply`, `knock_receipt`;
- валидировать ID, sequence, offsets, bounds и payload size;
- дедуплицировать входящие hits/replies в bounded cache;
- преобразовывать legacy `tap` в один средний `KnockHit`;
- сохранить отправку legacy `tap` как fallback для старого peer после version/capability negotiation.

**Проверка:** malformed input, duplicates, reordering, replay и legacy decode.

## Этап 3. Переиспользуемый Haptic Engine

**Файлы:**

- создать `lib/features/haptics/application/pulse_haptic_engine.dart`;
- создать `lib/features/haptics/infrastructure/platform_haptic_bridge.dart`;
- изменить `android/app/src/main/kotlin/io/pulseapp/pulse/MainActivity.kt`;
- создать `android/app/src/main/kotlin/io/pulseapp/pulse/PulseHapticEngine.kt`;
- создать `test/features/haptics/pulse_haptic_engine_test.dart`.

**Работа:**

- capability probe для vibrator, amplitude control и composition primitives;
- Tier A: `PRIMITIVE_CLICK`/`PRIMITIVE_THUD` composition при поддержке;
- Tier B: predefined/system clear effects;
- Tier C: no-op haptic с visual/audio fallback;
- отдельные команды soft/clear/deep/reply resonance;
- уважать системное отключение haptic и не использовать длинный legacy buzz.

**Проверка:** Dart fallback selection и Android capability logic; реальное качество отмечается как physical-device gate.

## Этап 4. Процедурный визуально-звуковой слой

**Файлы:**

- создать `lib/features/modes/presentation/modes/tap_tap/knock_surface_painter.dart`;
- создать `lib/features/modes/presentation/modes/tap_tap/knock_visual_state.dart`;
- при необходимости создать `lib/features/modes/infrastructure/tap_tap/knock_audio_bridge.dart` и Android engine;
- добавить только необходимые короткие локальные assets в `assets/sounds/` либо использовать нативный синтез.

**Работа:**

- деформация, contact glow, ripple и mutual bridge;
- один bounded ticker вместо animation controller на каждый завершённый hit;
- локальный/удалённый цветовой акцент;
- reduced-motion путь;
- короткий звук с transient/body/decay без микрофона и без постоянной audio session.

**Проверка:** painter/unit tests, golden states и frame stability.

## Этап 5. Перестройка Flutter-экрана

**Файлы:**

- изменить `lib/features/modes/presentation/modes/tap_tap_mode_screen.dart`;
- изменить `lib/l10n/app_ru.arb` и `lib/l10n/app_en.arb` либо актуальные ARB-файлы проекта;
- перегенерировать локализации;
- создать `test/modes/presentation/tap_tap_mode_screen_test.dart`.

**Работа:**

- сохранить одно полноэкранное действие без обязательных controls;
- перейти с `GestureDetector.onTapDown` на pointer lifecycle для duration/size/pressure;
- немедленная локальная реакция;
- отправка versioned hit и приём legacy/new событий;
- отображение серии и необязательного сохранения ритма;
- reply action и явное различие receipt/reply;
- semantics, large text, reduce motion и screen-size safety.

**Проверка:** local/remote/reply/rhythm widget tests, golden screenshots.

## Этап 6. Android protected lock-screen «Тук-Тук»

**Файлы:**

- создать `lib/features/lockscreen/application/lockscreen_knock_bridge.dart`;
- создать `android/app/src/main/kotlin/io/pulseapp/pulse/LockscreenKnockActivity.kt`;
- создать `android/app/src/main/kotlin/io/pulseapp/pulse/LockscreenKnockController.kt`;
- изменить `android/app/src/main/kotlin/io/pulseapp/pulse/MainActivity.kt`;
- изменить `android/app/src/main/AndroidManifest.xml`;
- изменить `lib/app.dart`.

**Работа:**

- пересылать только `knock_*` и legacy `tap` в изолированный native controller;
- `showWhenLocked`/`turnScreenOn`, без `requestDismissKeyguard`;
- один wake на серию, 30-секундный cooldown, максимум три wake bursts за 10 минут;
- тихий fallback notification при запрете full-screen;
- close/reply без доступа к приватной навигации;
- dedup до haptic/audio/wake;
- локализованный, доступный lock-screen UI.

**Проверка:** debug broadcast hook, Android unit/instrumented checks где доступны, adb lock/sleep flow.

## Этап 7. Сохранённые ритмы и безопасность

**Файлы:**

- создать `lib/features/modes/application/tap_tap/saved_rhythm_store.dart`;
- использовать существующее secure storage abstraction;
- добавить настройки контакта/тихих часов в существующий safety слой либо минимальный scoped store;
- создать тесты persistence/rate limit.

**Работа:**

- сохранение только по явному opt-in;
- хранить интервалы и нормализованный почерк, не сырые hardware values;
- не выводить личное название в обычное notification content;
- bounded history и удаление пользователем.

**Проверка:** round-trip, corrupt storage, delete и privacy defaults.

## Этап 8. Регрессия и автоматическая проверка

**Команды:**

- `dart format --set-exit-if-changed lib test` после форматирования;
- `flutter analyze`;
- `flutter test`;
- Android Kotlin compile/test tasks;
- targeted tests режима и event mapping.

**Обязательные сценарии:**

- single hit;
- 3-hit rhythm;
- duplicate/reorder;
- reply vs receipt;
- legacy peer;
- quiet hours/rate limit;
- haptic tiers A/B/C;
- reduced motion;
- app restart/reconnect.

## Этап 9. Два эмулятора

- запустить два AVD;
- установить одну debug/release candidate сборку;
- соединить два тестовых профиля;
- проверить foreground и locked-screen flows;
- во время серии переключить/разорвать сеть;
- проверить P2P/relay fallback;
- снять screenshots/video/logcat и event trace;
- подтвердить совпадение координат, порядка и ритма;
- отдельно зафиксировать, что эмулятор не подтверждает качество физического вибромотора.

## Этап 10. APK и завершение

- повторно выполнить анализ, тесты и release build;
- скопировать единственный актуальный APK в `artifacts/` под понятным именем;
- вычислить SHA-256;
- проверить установку APK;
- обновить QA backlog только реальными оставшимися physical-device ограничениями;
- закоммитить код и тесты;
- отправить изменения в настроенный Git remote;
- сообщить локальный путь к APK.

