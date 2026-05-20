/// Bluetooth Low Energy GATT identifiers for the Pulse direct transport.
///
/// These three UUIDs are part of the public over-the-air contract between
/// two paired Pulse devices and MUST remain stable across releases — they
/// are baked into peripheral advertising filters and central scan filters
/// on every shipped client. Bumping any of them is a breaking change that
/// requires a coordinated rollout across the App Store and Play Store.
///
/// The service UUID lives inside the Bluetooth SIG 16-bit "FEED" namespace
/// (`0xFEED`) expanded into the standard 128-bit form via the BT base UUID
/// `00000000-0000-1000-8000-00805f9b34fb`. The TX / RX characteristics use
/// random RFC-4122 v4 UUIDs so they never collide with any SIG-assigned
/// characteristic and remain unique to Pulse traffic.
library;

/// Primary GATT service advertised by Pulse peripherals and scanned for by
/// Pulse centrals. A scanning device that sees this service UUID can assume
/// it is looking at another Pulse client (the actual identity check is the
/// AES-256-GCM handshake from Track B).
const String pulseServiceUuid = '0000feed-0000-1000-8000-00805f9b34fb';

/// TX characteristic — peripheral → central direction.
///
/// The peripheral writes outbound frames here using `WRITE_WITHOUT_RESPONSE`
/// (no ACK, lowest latency) and the central observes notifications. We
/// deliberately do NOT use `INDICATE` here because Pulse already has its
/// own application-level acknowledgements via [PairChannel]'s nonce counter
/// and double-confirming every byte at the L2 layer just burns radio time.
const String pulseTxCharacteristicUuid = 'a1c1feed-0001-4001-8000-00805f9b34fb';

/// RX characteristic — central → peripheral direction.
///
/// The central writes outbound frames here. Pulse uses standard `WRITE`
/// (with response) for RX so the central learns about MTU / busy errors
/// synchronously, and additionally subscribes to `INDICATE` so the
/// peripheral can deliver back-pressure / flow-control signals later
/// without taking over the TX channel.
const String pulseRxCharacteristicUuid = 'a1c1feed-0002-4001-8000-00805f9b34fb';
