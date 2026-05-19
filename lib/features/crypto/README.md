# Pulse crypto layer — threat model & protocol

This package implements **Track B** of the Pulse audit: cryptographic pairing
and a sealed packet layer over an injectable transport. It is the sole
gate-keeper of confidentiality and authenticity for every byte that flows
between two paired devices.

## Protocol at a glance

```
┌────────────┐                              ┌────────────┐
│   Host A   │                              │  Partner B │
└────────────┘                              └────────────┘
      │   1. generate ephemeral X25519 keypair
      │   2. show QR `pulse://pair?v=1&pk=<pk_A_b64url>`
      │ ─────────────────────────  pk_A  ─────────────────▶
      │                                            │
      │                                3. generate ephemeral X25519 keypair
      │ ◀───────────────────────  pk_B  ─────────────────  │
      │                                            │
      │  4. shared = HKDF-SHA-256(                 │
      │         ikm = X25519(sk_A, pk_B),          │
      │         salt = "", info = "pulse:pair:v1:aead-key",
      │         out = 32 bytes)                    │
      │                                            │
      │  5. SAS = SHA-256("pulse:pair:v1:sas" || shared)[0..4] mod 10^6
      │     ── displayed as 6 decimal digits on both screens ──
      │                                            │
      │  6. user verifies SAS matches out-of-band  │
      │  7. PairKeys persisted to SecureKeyStore   │
```

After pairing, every payload is sealed with `AES-256-GCM`:

```
nonce(12) || ciphertext(N) || mac(16)
```

`nonce` is derived deterministically from a 64-bit monotonic counter (one per
direction). The high 32 bits of the 96-bit nonce field are reserved zero —
they exist to allow a future epoch/rekey bump without changing the wire
format.

## Threat model

### What we defend against

| Adversary capability                                | Mitigation                                                                                                           |
|-----------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Passive network observer                            | X25519 ECDH gives forward-secrecy per session; AES-GCM hides payloads.                                               |
| Active MitM swapping public keys                    | 6-digit SAS code is shown on both screens; user compares out-of-band. Mismatched code ⇒ abort.                       |
| Replay of a previously seen packet                  | `NonceCounter` rejects duplicates: `open()` requires the exact `expectedNonceCounter`. Replayed packets fail.        |
| Reordered packets                                   | Strict monotonic counter rejects out-of-order or lower-counter packets.                                              |
| Tampered ciphertext / MAC                           | AES-GCM authentication tag fails verification, `open()` throws.                                                      |
| Small-subgroup / low-order public-key attack        | `Curve25519PairingService.deriveSharedSecret` rejects all-zero ECDH output via `SmallSubgroupPublicKeyException`.    |
| Compromise of `SecureKeyStore` ⇒ nonce rollback     | `NonceCounter` writes a high-water mark first; `restore()` throws `NonceRollbackException` if HWM &gt; current.      |
| Stolen device, attacker reads keychain at rest      | iOS Keychain / Android EncryptedSharedPreferences (via `flutter_secure_storage`) provides at-rest encryption.        |
| User loses/sells device → must wipe                 | `PairKeys.wipe(store, connectionId)` removes shared key, partner public key, local private key, and both nonce HWMs. |

### What we do NOT defend against

- **Compromise of the host OS keychain or root.** If an attacker has
  arbitrary read on Keychain / KeyStore the shared key is exposed. We rely on
  the platform's hardware-backed keystore there.
- **Side-channel attacks on Dart's bignum.** The `cryptography` package falls
  back to pure-Dart X25519 on web; native iOS/Android paths use platform
  Curve25519 where available. Constant-time guarantees match the underlying
  library.
- **A malicious partner.** The other device is, by design, fully trusted once
  pairing is confirmed by the user comparing the SAS code. If the partner is
  compromised, no transport-level crypto can save us.
- **Coercion / "panic" attacks.** The §6 spec calls for a panic-wipe; we
  expose `PairKeys.wipe()` but the UI / shake-gesture binding lives in the
  app layer.

## File layout

| File                                  | Responsibility                                                                                |
|---------------------------------------|-----------------------------------------------------------------------------------------------|
| `curve25519_pairing_service.dart`     | X25519 keypair + ECDH + HKDF-SHA-256 + SAS code derivation.                                  |
| `aes_gcm_sealer.dart`                 | AES-256-GCM `seal`/`open` over `nonce || ciphertext || mac` with counter-derived nonces.     |
| `nonce_counter.dart`                  | Monotonic counter with CAS high-water-mark rollback detection. Persisted to SecureKeyStore.  |
| `pair_channel.dart`                   | Wraps any `RawByteChannel` and applies seal/open; emits a `Stream<PulsePacket>` upward.       |
| `demo_partner_channel.dart`           | In-memory `RawByteChannel` pair + `DemoPartnerHandshake` for the pre-transport demo flow.    |
| `pair_keys.dart`                      | Persistence model: shared key + ephemeral private + partner public; `persist/load/wipe`.     |

## Cryptographic parameters

| Parameter                          | Value                                       |
|------------------------------------|---------------------------------------------|
| Key exchange                       | X25519 (RFC 7748)                           |
| KDF                                | HKDF-SHA-256, salt = `""`, info = `"pulse:pair:v1:aead-key"` |
| AEAD                               | AES-256-GCM                                 |
| Key length                         | 32 bytes (256 bits)                         |
| Nonce length                       | 12 bytes (96 bits, high 32 = epoch reserved) |
| MAC tag length                     | 16 bytes (128 bits)                         |
| SAS context                        | SHA-256(`"pulse:pair:v1:sas"` ‖ shared), first 4 bytes as big-endian uint32 mod 10⁶ |
| RNG                                | `Random.secure()` (platform CSPRNG)         |
| Handshake timeout                  | 60 seconds (`kPairingHandshakeTimeout`)     |

## Performance budget

| Operation                                 | Pixel 5    | iPhone 11  | Budget   |
|-------------------------------------------|------------|------------|----------|
| Ephemeral X25519 keypair                  | ~5 ms      | ~3 ms      | < 25 ms  |
| ECDH + HKDF-SHA-256                       | ~15 ms     | ~10 ms     | < 50 ms  |
| SAS derivation                            | < 1 ms     | < 1 ms     | < 5 ms   |
| **Full pairing chain** (keypair + ECDH + HKDF + SAS) | **~35 ms** | **~25 ms** | **< 200 ms** |
| AES-GCM seal/open of a 1 KB packet        | < 1 ms     | < 1 ms     | < 5 ms   |

Numbers measured against the pure-Dart `cryptography` 2.7 backend. On
production builds with native curve25519 the keypair and ECDH steps drop
roughly 2×.

## Future hooks (deliberately out of scope for this PR)

- Replace `DemoPartnerHandshake` + `InMemoryByteChannel` with real BLE / mDNS
  / WebRTC transports (Track A follow-up).
- Move ECDH + HKDF onto a background `Isolate.run` if the pure-Dart curve
  ever drifts above 200 ms on low-end hardware.
- Rekey / epoch bump that uses the reserved high 32 bits of the AEAD nonce.
- Panic-wipe binding (shake gesture, secret pin) — wires `PairKeys.wipe`.
