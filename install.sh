#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if grep -qw 'snd_intel_dspcfg.dsp_driver=2' /proc/cmdline 2>/dev/null &&    arecord -l 2>/dev/null | grep -qE 'AVS DMIC|Digital Microphone'; then
  exec "$ROOT/scripts/fix-dmic-gain.sh"
fi

cat <<'EOM'
The AVS DMIC path is not active yet.
Stage 1 will switch this Acer Swift SF314-54 to Intel SST/AVS and install
missing AVS topology files. A reboot is required before the final gain fix.
EOM

exec "$ROOT/scripts/prepare-avs.sh"
