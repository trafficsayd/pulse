#!/usr/bin/env bash
# Regenerate the placeholder Sneak In sound effects.
#
# These are deliberately tiny, distinct sine-based tones — stand-ins until a
# real audio designer supplies the "deliberately silly" signals described in
# spec §7 / §8. Encoded as mono Opus @24 kbps (see spec §12).
#
# Requires: ffmpeg with libopus. Run from the repo root:
#   bash tool/gen_sneak_placeholder_sounds.sh
set -euo pipefail
out="assets/sounds/sneak"
mkdir -p "$out"
gen() { # name freq dur fade_start
  ffmpeg -y -f lavfi -i "sine=frequency=$2:duration=$3" \
    -af "afade=t=out:st=$4:d=0.08,volume=0.5" \
    -ac 1 -c:a libopus -b:a 24k "$out/$1.opus" >/dev/null 2>&1
  echo "  wrote $out/$1.opus"
}
gen knock   140 0.18 0.10
gen whistle 1300 0.40 0.32
gen bell    880 0.45 0.30
gen kiss    420 0.16 0.08
gen pop     600 0.10 0.04
gen giggle  520 0.35 0.27
gen meow    700 0.38 0.30
gen hiccup  340 0.14 0.06
echo "Done — 8 placeholder signals in $out/"
