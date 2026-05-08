/// Stable, top-level route paths.
///
/// Centralised so that deep links and tests can reference them by name
/// without typo'ing the path.
abstract final class Routes {
  static const pairing = '/pairing';
  static const hub = '/hub';
  static const people = '/people';
  static const subscription = '/subscription';
  static const sneakIn = '/sneak-in';
  static const mode = '/mode/:modeId';

  static String modePath(String modeId) => '/mode/$modeId';
}
