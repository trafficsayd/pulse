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
  String get transportRelayWebrtc => 'Интернет-реле (WebRTC)';

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
  String get modeSync => 'Синхро';

  @override
  String get tapTapHint => 'Коснитесь, чтобы постучать';

  @override
  String get halfHeartHint => 'Удерживай свою половину';

  @override
  String get sketchHint => 'Рисуй вживую или отправь готовую открытку';

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
  String get settingsCrashReports => 'Crash reports';

  @override
  String get settingsCrashReportsHint => 'Отправлять анонимно';

  @override
  String get connectionStatusTitle => 'Подключение';

  @override
  String get connectionStatusOfflineNotice =>
      'Приложение работает без интернета и не собирает данные';

  @override
  String get errorGeneric => 'Что-то пошло не так';
}
