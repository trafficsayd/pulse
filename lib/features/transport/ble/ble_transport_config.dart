/// Build-time flag controlling whether `BleTransport` instantiates the
/// real [RealBleClient] (talks to `flutter_blue_plus`) or the inert
/// [PlaceholderBleClient].
///
/// We expose this as a Dart compile-time constant rather than a runtime
/// flag so the placeholder code is tree-shaken out of release builds
/// where `useRealBleTransport` is `true`, and conversely so widget
/// tests / headless CI never link against the radio.
///
/// Default is `true` so release APKs / IPAs ship with the real BLE
/// transport. Tests override with `--dart-define=useRealBleTransport=false`
/// to keep the radio off in headless environments.
const bool useRealBleTransport = bool.fromEnvironment(
  'useRealBleTransport',
  defaultValue: true,
);
