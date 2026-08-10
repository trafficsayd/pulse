#!/usr/bin/env bash
# Regenerate the Sneak In sound effects.
#
# These are still synthesized stand-ins (not licensed sound design), but each
# is shaped to feel distinct and lively — a step up from plain sine tones —
# until a real audio pass lands.
#
# Format: mono AAC-LC in .m4a. Raw .opus is NOT decodable by the iOS system
# players (AVAudioPlayer/AVPlayer), so bundled SFX ship as AAC, which decodes
# natively on both platforms. Spec §12's Opus @24 kbps applies to the
# real-time session audio channel, not to bundled effects.
#
# Requires: ffmpeg with the native aac encoder. Run from the repo root:
#   bash tool/gen_sneak_placeholder_sounds.sh
set -euo pipefail
out="assets/sounds/sneak"
mkdir -p "$out"

gen() { # name  lavfi-source  filterchain
  ffmpeg -y -f lavfi -i "$2" -af "$3" -ac 1 -c:a aac -b:a 48k \
    -movflags +faststart "$out/$1.m4a" >/dev/null 2>&1
  echo "  wrote $out/$1.m4a"
}

# knock   — short woody tap (brown-noise burst through a lowpass)
gen knock   "anoisesrc=d=0.25:c=brown:a=0.5" "lowpass=f=320,aformat=channel_layouts=mono,atrim=0:0.22,volume=1.6,afade=t=out:st=0.16:d=0.05"
# whistle — bright rising tone
gen whistle "sine=frequency=900:d=0.4"       "vibrato=f=7:d=0.4,afade=t=in:st=0:d=0.03,afade=t=out:st=0.32:d=0.08,asetrate=48000*1.3,aresample=48000"
# bell    — 880 Hz shimmer with a long decay
gen bell    "sine=frequency=880:d=0.7"       "tremolo=f=6:d=0.3,afade=t=out:st=0.1:d=0.58,volume=0.6"
# kiss    — soft short high blip
gen kiss    "sine=frequency=520:d=0.18"      "afade=t=in:st=0:d=0.02,afade=t=out:st=0.06:d=0.1,volume=0.7"
# pop     — very short transient
gen pop     "anoisesrc=d=0.08:c=white:a=0.7" "highpass=f=500,afade=t=out:st=0.02:d=0.05,volume=1.5"
# giggle  — wobbly mid-tone bursts
gen giggle  "sine=frequency=560:d=0.4"       "tremolo=f=12:d=0.8,afade=t=out:st=0.3:d=0.1,volume=0.6"
# meow    — downward pitch slide
gen meow    "sine=frequency=760:d=0.38"      "vibrato=f=5:d=0.6,asetrate=48000*0.8,aresample=48000,afade=t=out:st=0.28:d=0.1,volume=0.7"
# hiccup  — tiny clipped blip
gen hiccup  "sine=frequency=380:d=0.16"      "afade=t=out:st=0.05:d=0.03,volume=0.8"

echo "Done — 8 Sneak In signals in $out/"
