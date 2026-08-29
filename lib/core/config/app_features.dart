/// Compile-time product switches.
///
/// Subscriptions deliberately stay disabled while Pulse is being polished and
/// tested. A future store build can restore the paywall without another code
/// change by compiling with:
///
/// `--dart-define=PULSE_SUBSCRIPTIONS_ENABLED=true`
abstract final class AppFeatures {
  static const bool subscriptionsEnabled = bool.fromEnvironment(
    'PULSE_SUBSCRIPTIONS_ENABLED',
    defaultValue: false,
  );

  /// In the current testing phase every mode and usage limit is open.
  static const bool unrestrictedTestingAccess = !subscriptionsEnabled;
}
