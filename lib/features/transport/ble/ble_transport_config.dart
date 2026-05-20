/// Build-time flag controlling whether `BleTransport` instantiates the
/// real [RealBleClient] (talks to `flutter_blue_plus`) or the inert
/// [PlaceholderBleClient].
///
/// We expose this as a Dart compile-time constant rather than a runtime
/// flag so the placeholder code is tree-shaken out of release builds
/// where `useRealBleTransport` is `true`, and conversely so widget
/// tests / headless CI never link against the radio.
///
/// Override with `--dart-define=useRealBleTransport=true` when building
/// release IPAs / APKs. Default is `false` so existing widget tests
/// and the CI smoke test keep their current behaviour.
const bool useRealBleTransport = bool.fromEnvironment(
  'useRealBleTransport',
  defaultValue: false,
);
