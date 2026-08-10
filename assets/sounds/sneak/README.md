# Sneak In — signal sounds

These `*.m4a` files are the 8 Sneak In signal sounds (knock, whistle, bell,
kiss, pop, giggle, meow, hiccup — see
`lib/features/sneak_in/presentation/sneak_signal_catalogue.dart`).

Encoding: mono AAC-LC in `.m4a`. Raw `.opus` is NOT decodable by the iOS
system players (AVAudioPlayer/AVPlayer), so bundled SFX ship as AAC —
spec §12's Opus @24 kbps applies to the real-time session audio channel,
not to bundled effects.

The current files are still **synthesized stand-ins** (shaped ffmpeg tones,
not licensed sound design). Regenerate any time with:

```bash
bash tool/gen_sneak_placeholder_sounds.sh
```

Replace with real sound design when ready. Keep the file names — the
catalogue `id` doubles as the on-the-wire protocol value and the asset
file name, and must not change.
