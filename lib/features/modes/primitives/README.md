# Mode primitives

Cross-cutting reusable building blocks for Pulse modes.

Each primitive:

1. **Has a tested fake.** Modes that want unit / widget tests don't open
   platform channels — they construct e.g. `FakeMicLevelStream` and push
   samples by hand.
2. **Cleans up.** Disposing the primitive must release every system
   resource it touched (mic, sensor, vibrator). The convention is
   `Future<void> dispose()`; callers `await` it inside `ConsumerStatefulWidget.dispose`
   via a `ref.onDispose` callback.
3. **Is capability-aware.** A primitive that needs hardware (mic,
   accel, vibration) checks `DeviceCapabilities` (see
   `lib/features/capabilities/`) before consuming it, and degrades to
   a no-op rather than throwing.

## Modules

| File | Purpose | Used by |
|------|---------|---------|
| `mic_level_stream.dart` | Normalized 0–1 microphone amplitude. | Whisper, Breath, Hum, Echo |
| `haptic_pattern_player.dart` | Sequenced vibration patterns with cancellation. | Half-Heart, Pulse-Thread, Sneak-In, Goosebumps |
| `painting_canvas.dart` | Stroke-based painting widget with stroke-finished callback. | Ray, Constellation, Doodle, Sketch |
| `accelerometer_3d_stream.dart` | 3-axis accelerometer with gravity-removed magnitude. | Balance, Cradle, Shake, Sync-tilt |

## Threat model — primitives

* **Microphone**: amplitude only, never raw audio. The recorder receives
  RMS power and discards the buffer. We do not write audio to disk and
  do not transmit it.
* **Accelerometer**: high-rate motion data leaves the phone only in
  abstract form (e.g. "shake event"), never raw samples.
* **Painting canvas**: stroke colors are public. Stroke timestamps are
  *not* transmitted — they're for local replay only.
* **Haptics**: patterns are public values; no covert channel.
