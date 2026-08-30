# Pulse QA backlog

## Critical — incoming Ray does not wake a fully dark locked screen

Reported behaviour: when the receiver phone is locked and its display is
completely off, drawing on the sender phone does not visibly wake the receiver
and nothing is shown on top of the lock screen.

This must be validated separately from the already covered case where the
keyguard is visible and the screen is on.

Acceptance flow:

1. Lock the receiver with a real PIN/pattern and wait until the display is off.
2. Keep Pulse backgrounded on the receiver; do not open its screen manually.
3. Start a live Ray stroke on the paired sender.
4. The receiver display wakes automatically.
5. The native Ray canvas appears above the keyguard and renders the stroke as
   it arrives.
6. Closing the Ray canvas returns to the still-locked system keyguard; it must
   never bypass device authentication.
7. Repeat in normal idle and forced deep Doze, with notifications allowed and
   denied, and record the OEM/battery-policy outcome.

Status: fixed in source and verified on the Android 14 emulator. The native
Ray bridge now treats both a locked keyguard and a non-interactive (fully
dark) display as presentation states, uses a bounded 15-second wake-up while
the secure Ray Activity opens, and keeps the canvas visible during the live
interaction. Verified for the first live point, a completed card, PIN
keyguard preservation after closing, and forced deep Doze. Physical OEM
verification remains required before release.
