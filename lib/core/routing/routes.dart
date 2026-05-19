/// Stable, top-level route paths.
///
/// Centralised so that deep links and tests can reference them by name
/// without typo'ing the path.
abstract final class Routes {
  static const pairing = '/pairing';
  static const connecting = '/connecting';
  static const hub = '/hub';
  static const people = '/people';
  static const subscription = '/subscription';
  static const sneakIn = '/sneak-in';
  static const sneakInIncoming = '/sneak-in/incoming';
  static const settings = '/settings';
  static const diagnostics = '/settings/diagnostics';
  static const connectionStatus = '/connection-status';
  static const modesCatalog = '/modes';
  static const connectionSettings = '/people/:connectionId/settings';
  static const mode = '/mode/:modeId';

  static String modePath(String modeId) => '/mode/$modeId';
  static String connectionSettingsPath(String connectionId) =>
      '/people/$connectionId/settings';
}
