/// Enumerates every hardware/OS capability that a Pulse mode can require.
///
/// Modes declare a [Set] of these in their [PulseModeDescriptor]; at boot
/// we probe the real device once and stash the result in a Riverpod
/// provider, so every place that has to decide "is this mode available"
/// (catalog grid, carousel, diagnostics screen, hub locked-state) reads
/// from the same source of truth.
///
/// Adding a new entry here is a real schema change — old values written
/// to disk (last-used-mode keying, locked-mode flags) reference these
/// names, so do NOT rename existing entries.
enum DeviceCapability {
  /// Has a microphone the app can record from. Used by Whisper / Breath /
  /// Whisper-Echo / Hum modes.
  microphone,

  /// Has an accelerometer / gyroscope. Used by Balance / Sync (tilt) /
  /// Cradle / Shake modes.
  accelerometer,

  /// Has a vibration motor.
  vibration,

  /// Has a vibration motor that supports per-pulse *amplitude* control
  /// (Android API 26+ / iPhone 7+ with Haptic Engine). Modes that
  /// degrade gracefully (Goosebumps, Bell strength) check for this
  /// before deciding between rich and stepped feedback.
  vibrationAmplitude,

  /// Has a flashlight / torch the app can toggle. Used by Morse / Thunder
  /// flash modes.
  flashlight,

  /// Has a camera the app can read frames from. Used by Lens mode.
  camera,

  /// Bluetooth Low Energy stack is present and usable. Used by every paired
  /// transport.
  bluetoothLe,

  /// Local network (Wi-Fi peer discovery via mDNS) is available. Used by
  /// LAN pair transport.
  localNetwork,
}

/// Snapshot of the real device's capabilities at app start.
///
/// Immutable on purpose — the user might grant/revoke permissions while
/// the app is running, but capability detection runs *after* the first
/// permission prompt and re-runs on `AppLifecycleState.resumed`. Replace
/// the whole snapshot rather than mutating in place; everything downstream
/// is reactive on the provider that owns this value.
class DeviceCapabilities {
  const DeviceCapabilities(this._available);

  /// Convenience constructor for tests / fallbacks: assume nothing is
  /// available. UI built around this still renders — every mode falls
  /// back to its placeholder state instead of crashing.
  const DeviceCapabilities.none() : _available = const <DeviceCapability>{};

  final Set<DeviceCapability> _available;

  /// True if [capability] is usable on this device.
  bool has(DeviceCapability capability) => _available.contains(capability);

  /// True if *every* capability in [required] is present. Modes use this
  /// to compute their available/locked state in one call.
  bool hasAll(Iterable<DeviceCapability> required) =>
      required.every(_available.contains);

  /// The capabilities in [required] that this device is missing. Used by
  /// the diagnostics screen to render "needs X" rows under each greyed-out
  /// mode tile.
  Set<DeviceCapability> missing(Iterable<DeviceCapability> required) {
    return required.where((c) => !_available.contains(c)).toSet();
  }

  /// Snapshot of every present capability. Defensive copy — callers must
  /// not mutate.
  Set<DeviceCapability> get all => Set.unmodifiable(_available);
}
