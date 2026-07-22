# Sneak In — placeholder sounds

These `*.opus` files are **placeholders**: short, distinct sine tones that stand
in for the real "deliberately silly" Sneak In signals (knock, whistle, bell,
kiss, pop, giggle, meow, hiccup — see `lib/features/sneak_in/presentation/sneak_signal_catalogue.dart`).

They exist so the asset references resolve and the Sneak In wheel can be wired
end-to-end before final audio is produced. Encoding: mono Opus @24 kbps (spec §12).

Regenerate any time with:

```bash
bash tool/gen_sneak_placeholder_sounds.sh
```

Replace with real sound design before store release. Keep the file names/ids —
`id` in the catalogue is part of the on-the-wire protocol and must not change.
