// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Pulse';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageEn => 'English';

  @override
  String get pairingTitle => 'Создать пару';

  @override
  String get pairingShareCode =>
      'Попросите партнёра ввести код или сканировать QR';

  @override
  String get pairingCreate => 'Создать пару';

  @override
  String get pairingJoin => 'Присоединиться';

  @override
  String get pairingEnterCode => 'Введите шестизначный код';

  @override
  String get pairingDerivingCode => 'Вычисляем безопасный код…';

  @override
  String get pairingError =>
      'Не удалось подключиться к серверу. Проверьте интернет и повторите.';

  @override
  String get pairingRetry => 'Повторить';

  @override
  String get pairingCancel => 'Отмена';

  @override
  String get pairingNicknameHint => 'Псевдоним (видно только тебе)';

  @override
  String get connectingTitle => 'Устанавливаем связь...';

  @override
  String get connectingKeyExchange => 'Обмен ключами';

  @override
  String get connectingChannelEncrypted => 'Шифрование канала';

  @override
  String get connectingSecuredLink => 'Создание защищённой связи';

  @override
  String get hubModesTitle => 'Режимы';

  @override
  String get hubLongPressToStart => 'Долгое нажатие — запустить';

  @override
  String get hubNoActiveConnection => 'Нет активной связи';

  @override
  String get hubChooseSomeone =>
      'Выбери человека в «Моих людях», чтобы начать сессию.';

  @override
  String get hubExit => 'Выйти в хаб';

  @override
  String get hubSubscriptionLockedHint => 'подписка';

  @override
  String get hubMore => 'Ещё';

  @override
  String get transportDirect => 'Прямое';

  @override
  String get transportLocal => 'Локальная сеть';

  @override
  String get transportRelay => 'Реле';

  @override
  String get transportSearching => 'Поиск';

  @override
  String get transportDirectBle => 'Прямое (BLE)';

  @override
  String get transportLocalWifi => 'Локальная сеть (Wi-Fi Direct)';

  @override
  String get transportRelayWebrtc => 'WebRTC (P2P / TURN)';

  @override
  String get peopleTitle => 'Мои люди';

  @override
  String get peopleEmpty => 'Пока нет сохранённых связей.';

  @override
  String get peopleAdd => 'Добавить';

  @override
  String get peopleLongPressHint => 'Долгое нажатие — меню действий';

  @override
  String get peopleMakeActive => 'Сделать активной';

  @override
  String get peopleSneakIn => 'Подкрасться';

  @override
  String get peoplePermissions => 'Разрешения';

  @override
  String get peopleArchive => 'Архивировать';

  @override
  String get peopleDelete => 'Удалить связь';

  @override
  String get peopleStatusActive => 'Активна';

  @override
  String get peopleStatusActiveWithYou => 'Активна с вами';

  @override
  String get peopleStatusPaused => 'Пауза';

  @override
  String get peopleStatusPausedSneakIn => 'Пауза • Sneak In ✓';

  @override
  String get peopleStatusArchived => 'Архив';

  @override
  String get navPeople => 'Мои люди';

  @override
  String get navPulse => 'Pulse';

  @override
  String get navSneakIn => 'Подкрасться';

  @override
  String get permissionsTitle => 'Разрешения';

  @override
  String get permissionsAllowSessions => 'Разрешить полные сессии';

  @override
  String get permissionsAllowSneakIn => 'Разрешить Sneak In';

  @override
  String get permissionsConfirmFirst =>
      'Требовать подтверждение при первом вмешательстве';

  @override
  String get permissionsBlocked => 'Заблокировано';

  @override
  String get connectionSettingsTitle => 'Настройки связи';

  @override
  String get connectionStatusSection => 'Статус';

  @override
  String get sneakInTitle => 'Подкрасться';

  @override
  String get sneakInChooseSound => 'Выберите звук';

  @override
  String get sneakInSwipeUp => 'Свайп вверх для отправки';

  @override
  String get sneakInLimitReached => 'Дневной лимит на этого человека исчерпан.';

  @override
  String sneakInRemaining(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Осталось $countString на сегодня',
      many: 'Осталось $countString на сегодня',
      few: 'Осталось $countString на сегодня',
      one: 'Осталось 1 на сегодня',
      zero: 'Сегодня больше нельзя',
    );
    return '$_temp0';
  }

  @override
  String get sneakInIncomingTitle => 'Sneak In!';

  @override
  String get sneakInIncomingSubtitle => 'отправил(а) вам сигнал';

  @override
  String get sneakInPullDownToReply => 'Потянуть вниз чтобы ответить';

  @override
  String get sneakInIgnore => 'Игнорировать';

  @override
  String get sneakSignalHiccup => 'Икота';

  @override
  String get sneakSignalToot => 'Пук';

  @override
  String get sneakSignalBell => 'Колокольчик';

  @override
  String get sneakSignalKnock => 'Стук';

  @override
  String get sneakSignalWhisper => 'Шёпот';

  @override
  String get sneakSignalClap => 'Хлопок';

  @override
  String get sneakSignalBoom => 'Бум';

  @override
  String get sneakSignalSqueak => 'Писк';

  @override
  String get subscriptionTitle => 'Подписка';

  @override
  String get subscriptionTagline => 'Откройте все режимы и возможности';

  @override
  String get subscriptionFeatureAllModes => 'Все режимы';

  @override
  String get subscriptionFeatureUnlimitedSneak => 'Безлимитный Sneak In';

  @override
  String get subscriptionFeatureUpToTen => 'До 10 сохранённых связей';

  @override
  String get subscriptionFeaturePriority => 'Приоритет новых функций';

  @override
  String get subscriptionPrice => '150 ₽ / месяц';

  @override
  String get subscriptionFreeTrial7Days => '7 дней бесплатно';

  @override
  String get subscriptionTryFree => 'Попробовать бесплатно';

  @override
  String get subscriptionContinueTrial => 'Продолжить триал';

  @override
  String get subscriptionSubscribe => 'Оформить подписку';

  @override
  String get subscriptionRestore => 'Восстановить покупки';

  @override
  String get subscriptionTermsOfUse => 'Условия использования';

  @override
  String get subscriptionPrivacyPolicy => 'Политика конфиденциальности';

  @override
  String get subscriptionLockedMode => 'Этот режим недоступен.';

  @override
  String subscriptionTrialDaysLeft(int days) {
    final intl.NumberFormat daysNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Осталось $daysString дней триала',
      many: 'Осталось $daysString дней триала',
      few: 'Осталось $daysString дня триала',
      one: 'Остался 1 день триала',
      zero: 'Триал заканчивается сегодня',
    );
    return '$_temp0';
  }

  @override
  String get subscriptionTrialExpired => 'Триал закончился';

  @override
  String get subscriptionConnectionLimitReached =>
      'Достигнут лимит связей для текущего тарифа.';

  @override
  String get subscriptionRestoring => 'Восстановление…';

  @override
  String get subscriptionRestoreNothing => 'Ничего не найдено';

  @override
  String get subscriptionRestoreSuccess => 'Подписка восстановлена';

  @override
  String get subscriptionPurchaseError => 'Не удалось оформить подписку';

  @override
  String get subscriptionPurchasePending => 'Платёж обрабатывается';

  @override
  String subscriptionActiveUntil(String date) {
    return 'Подписка активна до $date';
  }

  @override
  String get subscriptionManage => 'Управление подпиской';

  @override
  String get subscriptionErrorPaymentInvalid =>
      'Способ оплаты не поддерживается';

  @override
  String get subscriptionErrorPaymentNotAllowed =>
      'Покупки запрещены в настройках';

  @override
  String get subscriptionErrorBillingUnavailable =>
      'Магазин временно недоступен';

  @override
  String get subscriptionErrorItemUnavailable => 'Подписка пока недоступна';

  @override
  String get subscriptionErrorGeneric => 'Произошла ошибка. Попробуйте ещё раз';

  @override
  String get modesCatalogTitle => 'Режимы';

  @override
  String modesCatalogTrialSection(int available, int total) {
    return 'Доступно в триале ($available/$total)';
  }

  @override
  String get modesCatalogPaidSection => 'Доступно по подписке';

  @override
  String get modeTapTap => 'Тук-Тук';

  @override
  String get modeHalfHeart => 'Половина сердца';

  @override
  String get modeCandle => 'Свечка';

  @override
  String get modeWhisper => 'Шёпот';

  @override
  String get modeBell => 'Колокольчик';

  @override
  String get modeRay => 'Лучик';

  @override
  String get modeConstellation => 'Созвездие';

  @override
  String get modeGoosebumps => 'Мурашки';

  @override
  String get modeThread => 'Ниточка';

  @override
  String get modeThunder => 'Гром';

  @override
  String get modeFireworks => 'Фейерверк';

  @override
  String get modeBalance => 'Баланс';

  @override
  String get modeSandbox => 'Песочница';

  @override
  String get modeBreath => 'Дыхание';

  @override
  String get modeSync => 'Общий пульс';

  @override
  String get syncHintStart => 'Коснитесь экранов в одном ритме';

  @override
  String get syncHintListen => 'Слушайте ритм друг друга';

  @override
  String get syncHintCloser => 'Ваши ритмы сближаются';

  @override
  String get syncHintAlmost => 'Ещё немного';

  @override
  String get syncTogether => 'ВЫ ЧУВСТВУЕТЕ ОДИН РИТМ';

  @override
  String get syncHoldHint => 'Удерживайте экран, чтобы передать волну';

  @override
  String get tapTapHint => 'Коснитесь, чтобы постучать';

  @override
  String get halfHeartHint => 'Удерживай свою половину';

  @override
  String get sketchHint => 'Рисуй вживую или отправь готовую открытку';

  @override
  String get sketchCanvas => 'Холст';

  @override
  String get whisperHint => 'Шёпот в микрофон — лучи дышат вместе с тобой';

  @override
  String get bellHint => 'Потряси телефон, чтобы зазвонить';

  @override
  String get bellIntensity => 'Сила тряски';

  @override
  String get constellationHint => 'Касайся точек — подожди, чтобы соединить';

  @override
  String get candleTouchHint => 'Коснись, чтобы зажечь свечу';

  @override
  String get candleBlowHint => 'Подуй, чтобы погасить';

  @override
  String get candleCalibrating => 'Прислушиваемся к комнате…';

  @override
  String get candleTogether => 'ВЫ ЗАЖГЛИ ЕЁ ВМЕСТЕ';

  @override
  String get candleSoundOn => 'Включить звук свечи';

  @override
  String get candleSoundOff => 'Выключить звук свечи';

  @override
  String get candleClassic => 'Классика';

  @override
  String get candleGlass => 'Стекло';

  @override
  String get candleViolet => 'Фиолетовая';

  @override
  String get breathInhale => 'вдох';

  @override
  String get breathExhale => 'выдох';

  @override
  String get modesUnsupportedTitle => 'Здесь этот режим не работает';

  @override
  String modesUnsupportedNeeds(String what) {
    return 'Нужно: $what';
  }

  @override
  String get sketchLive => 'LIVE';

  @override
  String get sketchCard => 'Открытка';

  @override
  String get sketchClear => 'Очистить';

  @override
  String get sketchSend => 'Отправить';

  @override
  String get sketchSendReady => 'Рисунок готов к отправке';

  @override
  String get sketchEffectClean => 'Обычная кисть';

  @override
  String get sketchEffectNeon => 'Неон';

  @override
  String get sketchEffectGlow => 'Свечение';

  @override
  String get sketchEffectWatercolor => 'Акварель';

  @override
  String get sketchEffectSparkles => 'Блёстки';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageSection => 'Язык / Language';

  @override
  String get settingsLanguageSystem => 'Системный';

  @override
  String get settingsNotifications => 'Уведомления';

  @override
  String get settingsPermissions => 'Разрешения';

  @override
  String get settingsAbout => 'О приложении';

  @override
  String get settingsSupport => 'Служба поддержки';

  @override
  String settingsVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get settingsCrashReports => 'Отчёты о сбоях';

  @override
  String get settingsCrashReportsHint => 'Отправлять анонимно';

  @override
  String get settingsCrashReportsSection => 'Отчёты о сбоях';

  @override
  String get settingsPermissionBluetooth => 'Bluetooth';

  @override
  String get settingsPermissionWifi => 'Wi-Fi';

  @override
  String get settingsPermissionMicrophone => 'Микрофон';

  @override
  String get settingsPermissionGranted => 'Разрешено';

  @override
  String get settingsSupportEmail => 'support@pulse.app';

  @override
  String get connectionStatusTitle => 'Подключение';

  @override
  String get connectionStatusOfflineNotice =>
      'Приложение работает без интернета и не собирает данные';

  @override
  String get settingsDiagnostics => 'Диагностика устройства';

  @override
  String get settingsDiagnosticsHint =>
      'Какие функции доступны на твоём телефоне';

  @override
  String get diagnosticsTitle => 'Диагностика';

  @override
  String get diagnosticsHardwareSection => 'Оборудование';

  @override
  String get diagnosticsModesSection => 'Режимы';

  @override
  String get diagnosticsCapabilityMicrophone => 'Микрофон';

  @override
  String get diagnosticsCapabilityAccelerometer => 'Акселерометр';

  @override
  String get diagnosticsCapabilityVibration => 'Вибрация';

  @override
  String get diagnosticsCapabilityVibrationAmplitude => 'Тонкая вибрация';

  @override
  String get diagnosticsCapabilityFlashlight => 'Вспышка';

  @override
  String get diagnosticsCapabilityCamera => 'Камера';

  @override
  String get diagnosticsCapabilityBluetoothLe => 'Bluetooth LE';

  @override
  String get diagnosticsCapabilityLocalNetwork => 'Локальная сеть';

  @override
  String get diagnosticsStatusOk => 'Доступно';

  @override
  String get diagnosticsStatusMissing => 'Недоступно';

  @override
  String get diagnosticsStatusProbing => 'Проверка...';

  @override
  String get diagnosticsModeAvailable => 'Готово';

  @override
  String diagnosticsModeMissing(String what) {
    return 'Не хватает: $what';
  }

  @override
  String get modesUnavailableCaption => 'Недоступно на этом устройстве';

  @override
  String modesUnavailableReason(String what) {
    return 'Этому режиму нужен $what, которого нет на устройстве.';
  }

  @override
  String get errorGeneric => 'Что-то пошло не так';
}
