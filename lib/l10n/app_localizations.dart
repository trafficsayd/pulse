import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// App display name.
  ///
  /// In en, this message translates to:
  /// **'Pulse'**
  String get appTitle;

  /// No description provided for @languageRu.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRu;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @pairingTitle.
  ///
  /// In en, this message translates to:
  /// **'Create pair'**
  String get pairingTitle;

  /// No description provided for @pairingShareCode.
  ///
  /// In en, this message translates to:
  /// **'Ask your partner to enter the code or scan the QR'**
  String get pairingShareCode;

  /// No description provided for @pairingCreate.
  ///
  /// In en, this message translates to:
  /// **'Create pair'**
  String get pairingCreate;

  /// No description provided for @pairingJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get pairingJoin;

  /// No description provided for @pairingEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get pairingEnterCode;

  /// No description provided for @pairingDerivingCode.
  ///
  /// In en, this message translates to:
  /// **'Deriving secure code…'**
  String get pairingDerivingCode;

  /// No description provided for @pairingCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get pairingCancel;

  /// No description provided for @pairingNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Local nickname (only visible to you)'**
  String get pairingNicknameHint;

  /// No description provided for @connectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Establishing connection...'**
  String get connectingTitle;

  /// No description provided for @connectingKeyExchange.
  ///
  /// In en, this message translates to:
  /// **'Key exchange'**
  String get connectingKeyExchange;

  /// No description provided for @connectingChannelEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Channel encrypted'**
  String get connectingChannelEncrypted;

  /// No description provided for @connectingSecuredLink.
  ///
  /// In en, this message translates to:
  /// **'Secure link established'**
  String get connectingSecuredLink;

  /// No description provided for @hubModesTitle.
  ///
  /// In en, this message translates to:
  /// **'Modes'**
  String get hubModesTitle;

  /// No description provided for @hubLongPressToStart.
  ///
  /// In en, this message translates to:
  /// **'Long-press a mode to start'**
  String get hubLongPressToStart;

  /// No description provided for @hubNoActiveConnection.
  ///
  /// In en, this message translates to:
  /// **'No active connection'**
  String get hubNoActiveConnection;

  /// No description provided for @hubChooseSomeone.
  ///
  /// In en, this message translates to:
  /// **'Pick someone in My People to start a session.'**
  String get hubChooseSomeone;

  /// No description provided for @hubExit.
  ///
  /// In en, this message translates to:
  /// **'Exit to hub'**
  String get hubExit;

  /// No description provided for @hubSubscriptionLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get hubSubscriptionLockedHint;

  /// No description provided for @hubMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get hubMore;

  /// No description provided for @transportDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get transportDirect;

  /// No description provided for @transportLocal.
  ///
  /// In en, this message translates to:
  /// **'Local network'**
  String get transportLocal;

  /// No description provided for @transportRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get transportRelay;

  /// No description provided for @transportSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get transportSearching;

  /// No description provided for @transportDirectBle.
  ///
  /// In en, this message translates to:
  /// **'Direct (BLE)'**
  String get transportDirectBle;

  /// No description provided for @transportLocalWifi.
  ///
  /// In en, this message translates to:
  /// **'Local network (Wi-Fi Direct)'**
  String get transportLocalWifi;

  /// No description provided for @transportRelayWebrtc.
  ///
  /// In en, this message translates to:
  /// **'Internet relay (WebRTC)'**
  String get transportRelayWebrtc;

  /// No description provided for @peopleTitle.
  ///
  /// In en, this message translates to:
  /// **'My People'**
  String get peopleTitle;

  /// No description provided for @peopleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved connections yet.'**
  String get peopleEmpty;

  /// No description provided for @peopleAdd.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get peopleAdd;

  /// No description provided for @peopleLongPressHint.
  ///
  /// In en, this message translates to:
  /// **'Long press — action menu'**
  String get peopleLongPressHint;

  /// No description provided for @peopleMakeActive.
  ///
  /// In en, this message translates to:
  /// **'Make active'**
  String get peopleMakeActive;

  /// No description provided for @peopleSneakIn.
  ///
  /// In en, this message translates to:
  /// **'Sneak in'**
  String get peopleSneakIn;

  /// No description provided for @peoplePermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get peoplePermissions;

  /// No description provided for @peopleArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get peopleArchive;

  /// No description provided for @peopleDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete connection'**
  String get peopleDelete;

  /// No description provided for @peopleStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get peopleStatusActive;

  /// No description provided for @peopleStatusActiveWithYou.
  ///
  /// In en, this message translates to:
  /// **'Active with you'**
  String get peopleStatusActiveWithYou;

  /// No description provided for @peopleStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get peopleStatusPaused;

  /// No description provided for @peopleStatusPausedSneakIn.
  ///
  /// In en, this message translates to:
  /// **'Paused • Sneak In ✓'**
  String get peopleStatusPausedSneakIn;

  /// No description provided for @peopleStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get peopleStatusArchived;

  /// No description provided for @navPeople.
  ///
  /// In en, this message translates to:
  /// **'My People'**
  String get navPeople;

  /// No description provided for @navPulse.
  ///
  /// In en, this message translates to:
  /// **'Pulse'**
  String get navPulse;

  /// No description provided for @navSneakIn.
  ///
  /// In en, this message translates to:
  /// **'Sneak In'**
  String get navSneakIn;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsTitle;

  /// No description provided for @permissionsAllowSessions.
  ///
  /// In en, this message translates to:
  /// **'Allow full sessions'**
  String get permissionsAllowSessions;

  /// No description provided for @permissionsAllowSneakIn.
  ///
  /// In en, this message translates to:
  /// **'Allow Sneak In'**
  String get permissionsAllowSneakIn;

  /// No description provided for @permissionsConfirmFirst.
  ///
  /// In en, this message translates to:
  /// **'Confirm first sneak in'**
  String get permissionsConfirmFirst;

  /// No description provided for @permissionsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get permissionsBlocked;

  /// No description provided for @connectionSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection settings'**
  String get connectionSettingsTitle;

  /// No description provided for @connectionStatusSection.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get connectionStatusSection;

  /// No description provided for @sneakInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sneak in'**
  String get sneakInTitle;

  /// No description provided for @sneakInChooseSound.
  ///
  /// In en, this message translates to:
  /// **'Pick a sound'**
  String get sneakInChooseSound;

  /// No description provided for @sneakInSwipeUp.
  ///
  /// In en, this message translates to:
  /// **'Swipe up to send'**
  String get sneakInSwipeUp;

  /// No description provided for @sneakInLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached today\'s limit for this person.'**
  String get sneakInLimitReached;

  /// No description provided for @sneakInRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sneak ins left today} =1{1 sneak in left today} other{{count} sneak ins left today}}'**
  String sneakInRemaining(int count);

  /// No description provided for @sneakInIncomingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sneak In!'**
  String get sneakInIncomingTitle;

  /// No description provided for @sneakInIncomingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'sent you a signal'**
  String get sneakInIncomingSubtitle;

  /// No description provided for @sneakInPullDownToReply.
  ///
  /// In en, this message translates to:
  /// **'Pull down to reply'**
  String get sneakInPullDownToReply;

  /// No description provided for @sneakInIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get sneakInIgnore;

  /// No description provided for @sneakSignalHiccup.
  ///
  /// In en, this message translates to:
  /// **'Hiccup'**
  String get sneakSignalHiccup;

  /// No description provided for @sneakSignalToot.
  ///
  /// In en, this message translates to:
  /// **'Toot'**
  String get sneakSignalToot;

  /// No description provided for @sneakSignalBell.
  ///
  /// In en, this message translates to:
  /// **'Bell'**
  String get sneakSignalBell;

  /// No description provided for @sneakSignalKnock.
  ///
  /// In en, this message translates to:
  /// **'Knock'**
  String get sneakSignalKnock;

  /// No description provided for @sneakSignalWhisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get sneakSignalWhisper;

  /// No description provided for @sneakSignalClap.
  ///
  /// In en, this message translates to:
  /// **'Clap'**
  String get sneakSignalClap;

  /// No description provided for @sneakSignalBoom.
  ///
  /// In en, this message translates to:
  /// **'Boom'**
  String get sneakSignalBoom;

  /// No description provided for @sneakSignalSqueak.
  ///
  /// In en, this message translates to:
  /// **'Squeak'**
  String get sneakSignalSqueak;

  /// No description provided for @subscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscriptionTitle;

  /// No description provided for @subscriptionTagline.
  ///
  /// In en, this message translates to:
  /// **'Unlock every mode and feature'**
  String get subscriptionTagline;

  /// No description provided for @subscriptionFeatureAllModes.
  ///
  /// In en, this message translates to:
  /// **'All modes'**
  String get subscriptionFeatureAllModes;

  /// No description provided for @subscriptionFeatureUnlimitedSneak.
  ///
  /// In en, this message translates to:
  /// **'Unlimited Sneak In'**
  String get subscriptionFeatureUnlimitedSneak;

  /// No description provided for @subscriptionFeatureUpToTen.
  ///
  /// In en, this message translates to:
  /// **'Up to 10 saved connections'**
  String get subscriptionFeatureUpToTen;

  /// No description provided for @subscriptionFeaturePriority.
  ///
  /// In en, this message translates to:
  /// **'Priority on new features'**
  String get subscriptionFeaturePriority;

  /// No description provided for @subscriptionPrice.
  ///
  /// In en, this message translates to:
  /// **'150 ₽ / month'**
  String get subscriptionPrice;

  /// Price line when store metadata is available; price is the store-localised price string.
  ///
  /// In en, this message translates to:
  /// **'{price} / month'**
  String subscriptionPricePerMonth(String price);

  /// No description provided for @subscriptionFreeTrial7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days free'**
  String get subscriptionFreeTrial7Days;

  /// No description provided for @subscriptionTryFree.
  ///
  /// In en, this message translates to:
  /// **'Try for free'**
  String get subscriptionTryFree;

  /// No description provided for @subscriptionContinueTrial.
  ///
  /// In en, this message translates to:
  /// **'Continue trial'**
  String get subscriptionContinueTrial;

  /// No description provided for @subscriptionSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscriptionSubscribe;

  /// No description provided for @subscriptionRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get subscriptionRestore;

  /// No description provided for @subscriptionTermsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get subscriptionTermsOfUse;

  /// No description provided for @subscriptionPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get subscriptionPrivacyPolicy;

  /// No description provided for @subscriptionLockedMode.
  ///
  /// In en, this message translates to:
  /// **'This mode is locked.'**
  String get subscriptionLockedMode;

  /// No description provided for @subscriptionTrialDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Trial ends today} =1{1 day of trial left} other{{days} days of trial left}}'**
  String subscriptionTrialDaysLeft(int days);

  /// No description provided for @subscriptionTrialExpired.
  ///
  /// In en, this message translates to:
  /// **'Trial expired'**
  String get subscriptionTrialExpired;

  /// No description provided for @subscriptionConnectionLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the connection limit for your tier.'**
  String get subscriptionConnectionLimitReached;

  /// No description provided for @subscriptionRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get subscriptionRestoring;

  /// No description provided for @subscriptionRestoreNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to restore'**
  String get subscriptionRestoreNothing;

  /// No description provided for @subscriptionRestoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Subscription restored'**
  String get subscriptionRestoreSuccess;

  /// No description provided for @subscriptionPurchaseError.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the purchase'**
  String get subscriptionPurchaseError;

  /// No description provided for @subscriptionPurchasePending.
  ///
  /// In en, this message translates to:
  /// **'Payment is processing'**
  String get subscriptionPurchasePending;

  /// No description provided for @subscriptionActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Subscription active until {date}'**
  String subscriptionActiveUntil(String date);

  /// No description provided for @subscriptionManage.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get subscriptionManage;

  /// No description provided for @subscriptionErrorPaymentInvalid.
  ///
  /// In en, this message translates to:
  /// **'Payment method is not supported'**
  String get subscriptionErrorPaymentInvalid;

  /// No description provided for @subscriptionErrorPaymentNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Purchases are disabled in settings'**
  String get subscriptionErrorPaymentNotAllowed;

  /// No description provided for @subscriptionErrorBillingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Store is temporarily unavailable'**
  String get subscriptionErrorBillingUnavailable;

  /// No description provided for @subscriptionErrorItemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Subscription is not available yet'**
  String get subscriptionErrorItemUnavailable;

  /// No description provided for @subscriptionErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong, please try again'**
  String get subscriptionErrorGeneric;

  /// No description provided for @modesCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Modes'**
  String get modesCatalogTitle;

  /// No description provided for @modesCatalogTrialSection.
  ///
  /// In en, this message translates to:
  /// **'Available in trial ({available}/{total})'**
  String modesCatalogTrialSection(int available, int total);

  /// No description provided for @modesCatalogPaidSection.
  ///
  /// In en, this message translates to:
  /// **'Available with subscription'**
  String get modesCatalogPaidSection;

  /// No description provided for @modeTapTap.
  ///
  /// In en, this message translates to:
  /// **'Knock-Knock'**
  String get modeTapTap;

  /// No description provided for @modeHalfHeart.
  ///
  /// In en, this message translates to:
  /// **'Half-Heart'**
  String get modeHalfHeart;

  /// No description provided for @modeCandle.
  ///
  /// In en, this message translates to:
  /// **'Candle'**
  String get modeCandle;

  /// No description provided for @modeWhisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get modeWhisper;

  /// No description provided for @modeBell.
  ///
  /// In en, this message translates to:
  /// **'Bell'**
  String get modeBell;

  /// No description provided for @modeRay.
  ///
  /// In en, this message translates to:
  /// **'Ray'**
  String get modeRay;

  /// No description provided for @modeConstellation.
  ///
  /// In en, this message translates to:
  /// **'Constellation'**
  String get modeConstellation;

  /// No description provided for @modeGoosebumps.
  ///
  /// In en, this message translates to:
  /// **'Goosebumps'**
  String get modeGoosebumps;

  /// No description provided for @modeThread.
  ///
  /// In en, this message translates to:
  /// **'Thread'**
  String get modeThread;

  /// No description provided for @modeThunder.
  ///
  /// In en, this message translates to:
  /// **'Thunder'**
  String get modeThunder;

  /// No description provided for @modeFireworks.
  ///
  /// In en, this message translates to:
  /// **'Fireworks'**
  String get modeFireworks;

  /// No description provided for @modeBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get modeBalance;

  /// No description provided for @modeSandbox.
  ///
  /// In en, this message translates to:
  /// **'Sandbox'**
  String get modeSandbox;

  /// No description provided for @modeBreath.
  ///
  /// In en, this message translates to:
  /// **'Breath'**
  String get modeBreath;

  /// No description provided for @modeSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get modeSync;

  /// No description provided for @tapTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to knock'**
  String get tapTapHint;

  /// No description provided for @halfHeartHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the half on your side'**
  String get halfHeartHint;

  /// No description provided for @sketchHint.
  ///
  /// In en, this message translates to:
  /// **'Draw live or send a finished card'**
  String get sketchHint;

  /// No description provided for @whisperHint.
  ///
  /// In en, this message translates to:
  /// **'Whisper into the mic — the spokes follow your breath'**
  String get whisperHint;

  /// No description provided for @bellHint.
  ///
  /// In en, this message translates to:
  /// **'Shake to ring the bell'**
  String get bellHint;

  /// No description provided for @bellIntensity.
  ///
  /// In en, this message translates to:
  /// **'Shake intensity'**
  String get bellIntensity;

  /// No description provided for @constellationHint.
  ///
  /// In en, this message translates to:
  /// **'Tap stars — wait to draw the lines'**
  String get constellationHint;

  /// No description provided for @candleTouchHint.
  ///
  /// In en, this message translates to:
  /// **'Touch to light the candle'**
  String get candleTouchHint;

  /// No description provided for @candleBlowHint.
  ///
  /// In en, this message translates to:
  /// **'Blow to extinguish'**
  String get candleBlowHint;

  /// No description provided for @modesUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'This mode can\'t run here'**
  String get modesUnsupportedTitle;

  /// No description provided for @modesUnsupportedNeeds.
  ///
  /// In en, this message translates to:
  /// **'Needs: {what}'**
  String modesUnsupportedNeeds(String what);

  /// No description provided for @sketchLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get sketchLive;

  /// No description provided for @sketchCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get sketchCard;

  /// No description provided for @sketchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get sketchClear;

  /// No description provided for @sketchSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sketchSend;

  /// No description provided for @sketchSendReady.
  ///
  /// In en, this message translates to:
  /// **'Sketch prepared for sending'**
  String get sketchSendReady;

  /// No description provided for @sketchEffectClean.
  ///
  /// In en, this message translates to:
  /// **'Clean brush'**
  String get sketchEffectClean;

  /// No description provided for @sketchEffectNeon.
  ///
  /// In en, this message translates to:
  /// **'Neon'**
  String get sketchEffectNeon;

  /// No description provided for @sketchEffectGlow.
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get sketchEffectGlow;

  /// No description provided for @sketchEffectWatercolor.
  ///
  /// In en, this message translates to:
  /// **'Watercolor'**
  String get sketchEffectWatercolor;

  /// No description provided for @sketchEffectSparkles.
  ///
  /// In en, this message translates to:
  /// **'Sparkles'**
  String get sketchEffectSparkles;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language / Язык'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get settingsPermissions;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsCrashReports.
  ///
  /// In en, this message translates to:
  /// **'Crash reports'**
  String get settingsCrashReports;

  /// No description provided for @settingsCrashReportsHint.
  ///
  /// In en, this message translates to:
  /// **'Send anonymously'**
  String get settingsCrashReportsHint;

  /// No description provided for @settingsCrashReportsSection.
  ///
  /// In en, this message translates to:
  /// **'Crash reports'**
  String get settingsCrashReportsSection;

  /// No description provided for @settingsPermissionBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get settingsPermissionBluetooth;

  /// No description provided for @settingsPermissionWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get settingsPermissionWifi;

  /// No description provided for @settingsPermissionMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsPermissionMicrophone;

  /// No description provided for @settingsPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get settingsPermissionGranted;

  /// No description provided for @settingsSupportEmail.
  ///
  /// In en, this message translates to:
  /// **'support@pulse.app'**
  String get settingsSupportEmail;

  /// No description provided for @connectionStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionStatusTitle;

  /// No description provided for @connectionStatusOfflineNotice.
  ///
  /// In en, this message translates to:
  /// **'The app works offline and collects no data'**
  String get connectionStatusOfflineNotice;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Device diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @settingsDiagnosticsHint.
  ///
  /// In en, this message translates to:
  /// **'What works on this phone'**
  String get settingsDiagnosticsHint;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsHardwareSection.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get diagnosticsHardwareSection;

  /// No description provided for @diagnosticsModesSection.
  ///
  /// In en, this message translates to:
  /// **'Modes'**
  String get diagnosticsModesSection;

  /// No description provided for @diagnosticsCapabilityMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get diagnosticsCapabilityMicrophone;

  /// No description provided for @diagnosticsCapabilityAccelerometer.
  ///
  /// In en, this message translates to:
  /// **'Accelerometer'**
  String get diagnosticsCapabilityAccelerometer;

  /// No description provided for @diagnosticsCapabilityVibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get diagnosticsCapabilityVibration;

  /// No description provided for @diagnosticsCapabilityVibrationAmplitude.
  ///
  /// In en, this message translates to:
  /// **'Variable vibration'**
  String get diagnosticsCapabilityVibrationAmplitude;

  /// No description provided for @diagnosticsCapabilityFlashlight.
  ///
  /// In en, this message translates to:
  /// **'Flashlight'**
  String get diagnosticsCapabilityFlashlight;

  /// No description provided for @diagnosticsCapabilityCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get diagnosticsCapabilityCamera;

  /// No description provided for @diagnosticsCapabilityBluetoothLe.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth LE'**
  String get diagnosticsCapabilityBluetoothLe;

  /// No description provided for @diagnosticsCapabilityLocalNetwork.
  ///
  /// In en, this message translates to:
  /// **'Local network'**
  String get diagnosticsCapabilityLocalNetwork;

  /// No description provided for @diagnosticsStatusOk.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get diagnosticsStatusOk;

  /// No description provided for @diagnosticsStatusMissing.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get diagnosticsStatusMissing;

  /// No description provided for @diagnosticsStatusProbing.
  ///
  /// In en, this message translates to:
  /// **'Probing…'**
  String get diagnosticsStatusProbing;

  /// No description provided for @diagnosticsModeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get diagnosticsModeAvailable;

  /// No description provided for @diagnosticsModeMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing: {what}'**
  String diagnosticsModeMissing(String what);

  /// No description provided for @modesUnavailableCaption.
  ///
  /// In en, this message translates to:
  /// **'Unavailable on this device'**
  String get modesUnavailableCaption;

  /// No description provided for @modesUnavailableReason.
  ///
  /// In en, this message translates to:
  /// **'This mode needs {what}, which isn\'t available on this device.'**
  String modesUnavailableReason(String what);

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @verifyCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Make sure it\'s really them'**
  String get verifyCodeTitle;

  /// No description provided for @verifyCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Check that this code is identical to the one shown on your partner\'s screen.'**
  String get verifyCodeBody;

  /// No description provided for @verifyCodeMatch.
  ///
  /// In en, this message translates to:
  /// **'The codes match'**
  String get verifyCodeMatch;

  /// No description provided for @verifyCodeMismatch.
  ///
  /// In en, this message translates to:
  /// **'They don\'t match'**
  String get verifyCodeMismatch;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
