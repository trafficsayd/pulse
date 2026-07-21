/// Lifecycle status of a saved connection.
///
/// Mirrors the spec's three states:
/// - [active]    — full duplex; the only connection at a time may be active.
/// - [paused]    — shadow channel only; can receive Sneak In signals.
/// - [archived]  — no auto-reconnect; nothing comes through.
enum ConnectionStatus {
  active,
  paused,
  archived;

  static ConnectionStatus fromName(String name) {
    return ConnectionStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ConnectionStatus.paused,
    );
  }
}
