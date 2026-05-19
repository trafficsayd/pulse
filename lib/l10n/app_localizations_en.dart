import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pulse';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageEn => 'English';

  @override
  String get pairingTitle => 'Create pair';

  @override
  String get pairingShareCode =>
      'Ask your partner to enter the code or scan the QR';

  @override
  String get pairingCreate => 'Create pair';

  @override
  String get pairingJoin => 'Join';

  @override
  String get pairingEnterCode => 'Enter the 6-digit code';

  @override
  String get pairingCancel => 'Cancel';

  @override
  String get pairingNicknameHint => 'Local nickname (only visible to you)';

  @override
  String get connectingTitle => 'Establishing connection...';

  @override
  String get connectingKeyExchange => 'Key exchange';

  @override
  String get connectingChannelEncrypted => 'Channel encrypted';

  @override
  String get connectingSecuredLink => 'Secure link established';

  @override
  String get hubModesTitle => 'Modes';

  @override
  String get hubLongPressToStart => 'Long-press a mode to start';

  @override
  String get hubNoActiveConnection => 'No active connection';

  @override
  String get hubChooseSomeone =>
      'Pick someone in My People to start a session.';

  @override
  String get hubExit => 'Exit to hub';

  @override
  String get hubSubscriptionLockedHint => 'Subscription';

  @override
  String get hubMore => 'More';

  @override
  String get transportDirect => 'Direct';

  @override
  String get transportLocal => 'Local network';

  @override
  String get transportRelay => 'Relay';

  @override
  String get transportSearching => 'Searching';

  @override
  String get transportDirectBle => 'Direct (BLE)';

  @override
  String get transportLocalWifi => 'Local network (Wi-Fi Direct)';

  @override
  String get transportRelayWebrtc => 'Internet relay (WebRTC)';

  @override
  String get peopleTitle => 'My People';

  @override
  String get peopleEmpty => 'No saved connections yet.';

  @override
  String get peopleAdd => 'Add person';

  @override
  String get peopleLongPressHint => 'Long press — action menu';

  @override
  String get peopleMakeActive => 'Make active';

  @override
  String get peopleSneakIn => 'Sneak in';

  @override
  String get peoplePermissions => 'Permissions';

  @override
  String get peopleArchive => 'Archive';

  @override
  String get peopleDelete => 'Delete connection';

  @override
  String get peopleStatusActive => 'Active';

  @override
  String get peopleStatusActiveWithYou => 'Active with you';

  @override
  String get peopleStatusPaused => 'Paused';

  @override
  String get peopleStatusPausedSneakIn => 'Paused • Sneak In ✓';

  @override
  String get peopleStatusArchived => 'Archived';

  @override
  String get navPeople => 'My People';

  @override
  String get navPulse => 'Pulse';

  @override
  String get navSneakIn => 'Sneak In';

  @override
  String get permissionsTitle => 'Permissions';

  @override
  String get permissionsAllowSessions => 'Allow full sessions';

  @override
  String get permissionsAllowSneakIn => 'Allow Sneak In';

  @override
  String get permissionsConfirmFirst => 'Confirm first sneak in';

  @override
  String get permissionsBlocked => 'Blocked';

  @override
  String get connectionSettingsTitle => 'Connection settings';

  @override
  String get connectionStatusSection => 'Status';

  @override
  String get sneakInTitle => 'Sneak in';

  @override
  String get sneakInChooseSound => 'Pick a sound';

  @override
  String get sneakInSwipeUp => 'Swipe up to send';

  @override
  String get sneakInLimitReached =>
      'You\'ve reached today\'s limit for this person.';

  @override
  String sneakInRemaining(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString sneak ins left today',
      one: '1 sneak in left today',
      zero: 'No sneak ins left today',
    );
    return '$_temp0';
  }

  @override
  String get sneakInIncomingTitle => 'Sneak In!';

  @override
  String get sneakInIncomingSubtitle => 'sent you a signal';

  @override
  String get sneakInPullDownToReply => 'Pull down to reply';

  @override
  String get sneakInIgnore => 'Ignore';

  @override
  String get sneakSignalHiccup => 'Hiccup';

  @override
  String get sneakSignalToot => 'Toot';

  @override
  String get sneakSignalBell => 'Bell';

  @override
  String get sneakSignalKnock => 'Knock';

  @override
  String get sneakSignalWhisper => 'Whisper';

  @override
  String get sneakSignalClap => 'Clap';

  @override
  String get sneakSignalBoom => 'Boom';

  @override
  String get sneakSignalSqueak => 'Squeak';

  @override
  String get subscriptionTitle => 'Subscription';

  @override
  String get subscriptionTagline => 'Unlock every mode and feature';

  @override
  String get subscriptionFeatureAllModes => 'All modes';

  @override
  String get subscriptionFeatureUnlimitedSneak => 'Unlimited Sneak In';

  @override
  String get subscriptionFeatureUpToTen => 'Up to 10 saved connections';

  @override
  String get subscriptionFeaturePriority => 'Priority on new features';

  @override
  String get subscriptionPrice => '150 ₽ / month';

  @override
  String get subscriptionFreeTrial7Days => '7 days free';

  @override
  String get subscriptionTryFree => 'Try for free';

  @override
  String get subscriptionContinueTrial => 'Continue trial';

  @override
  String get subscriptionSubscribe => 'Subscribe';

  @override
  String get subscriptionRestore => 'Restore purchases';

  @override
  String get subscriptionTermsOfUse => 'Terms of use';

  @override
  String get subscriptionPrivacyPolicy => 'Privacy policy';

  @override
  String get subscriptionLockedMode => 'This mode is locked.';

  @override
  String subscriptionTrialDaysLeft(int days) {
    final intl.NumberFormat daysNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$daysString days of trial left',
      one: '1 day of trial left',
      zero: 'Trial ends today',
    );
    return '$_temp0';
  }

  @override
  String get subscriptionTrialExpired => 'Trial expired';

  @override
  String get subscriptionConnectionLimitReached =>
      'You\'ve reached the connection limit for your tier.';

  @override
  String get subscriptionRestoring => 'Restoring…';

  @override
  String get subscriptionRestoreNothing => 'Nothing to restore';

  @override
  String get subscriptionRestoreSuccess => 'Subscription restored';

  @override
  String get subscriptionPurchaseError => 'Could not complete the purchase';

  @override
  String get subscriptionPurchasePending => 'Payment is processing';

  @override
  String subscriptionActiveUntil(String date) {
    return 'Subscription active until $date';
  }

  @override
  String get subscriptionManage => 'Manage subscription';

  @override
  String get subscriptionErrorPaymentInvalid =>
      'Payment method is not supported';

  @override
  String get subscriptionErrorPaymentNotAllowed =>
      'Purchases are disabled in settings';

  @override
  String get subscriptionErrorBillingUnavailable =>
      'Store is temporarily unavailable';

  @override
  String get subscriptionErrorItemUnavailable =>
      'Subscription is not available yet';

  @override
  String get subscriptionErrorGeneric =>
      'Something went wrong, please try again';

  @override
  String get modesCatalogTitle => 'Modes';

  @override
  String modesCatalogTrialSection(int available, int total) {
    return 'Available in trial ($available/$total)';
  }

  @override
  String get modesCatalogPaidSection => 'Available with subscription';

  @override
  String get modeTapTap => 'Knock-Knock';

  @override
  String get modeHalfHeart => 'Half-Heart';

  @override
  String get modeCandle => 'Candle';

  @override
  String get modeWhisper => 'Whisper';

  @override
  String get modeBell => 'Bell';

  @override
  String get modeRay => 'Ray';

  @override
  String get modeConstellation => 'Constellation';

  @override
  String get modeGoosebumps => 'Goosebumps';

  @override
  String get modeThread => 'Thread';

  @override
  String get modeThunder => 'Thunder';

  @override
  String get modeFireworks => 'Fireworks';

  @override
  String get modeBalance => 'Balance';

  @override
  String get modeSandbox => 'Sandbox';

  @override
  String get modeBreath => 'Breath';

  @override
  String get modeSync => 'Sync';

  @override
  String get tapTapHint => 'Tap to knock';

  @override
  String get halfHeartHint => 'Hold the half on your side';

  @override
  String get sketchHint => 'Draw live or send a finished card';

  @override
  String get sketchLive => 'LIVE';

  @override
  String get sketchCard => 'Card';

  @override
  String get sketchClear => 'Clear';

  @override
  String get sketchSend => 'Send';

  @override
  String get sketchSendReady => 'Sketch prepared for sending';

  @override
  String get sketchEffectClean => 'Clean brush';

  @override
  String get sketchEffectNeon => 'Neon';

  @override
  String get sketchEffectGlow => 'Glow';

  @override
  String get sketchEffectWatercolor => 'Watercolor';

  @override
  String get sketchEffectSparkles => 'Sparkles';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSection => 'Language / Язык';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsPermissions => 'Permissions';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsSupport => 'Support';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsCrashReports => 'Crash reports';

  @override
  String get settingsCrashReportsHint => 'Send anonymously';

  @override
  String get connectionStatusTitle => 'Connection';

  @override
  String get connectionStatusOfflineNotice =>
      'The app works offline and collects no data';

  @override
  String get errorGeneric => 'Something went wrong';
}
