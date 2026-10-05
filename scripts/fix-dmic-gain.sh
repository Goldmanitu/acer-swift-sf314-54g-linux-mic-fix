#!/usr/bin/env bash
set -u

STAMP="$(date +%Y%m%d-%H%M%S)"
BASE="${XDG_STATE_HOME:-$HOME/.local/state}/acer-sf314-mic-fix"
mkdir -p "$BASE"
LOG="$BASE/fix-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

say(){ printf '\n=== %s ===\n' "$*"; }
ok(){ printf '[OK] %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*"; }
fail(){ printf '[FAIL] %s\n' "$*"; }

MODE="${1:-apply}"

find_dmic_card() {
  local txt card
  txt="$(arecord -l 2>/dev/null || true)"
  card="$(printf '%s\n' "$txt" | sed -n 's/^карта \([0-9][0-9]*\): DMIC .*/\1/p' | head -n1)"
  [ -n "$card" ] || card="$(printf '%s\n' "$txt" | sed -n 's/^card \([0-9][0-9]*\): DMIC .*/\1/p' | head -n1)"
  printf '%s' "$card"
}

find_dmic_source() {
  pactl list short sources 2>/dev/null | awk '$2 ~ /avs_dmic/ {print $2; exit}'
}

wav_stats() {
  local wav="$1"
  if [ ! -s "$wav" ]; then
    echo "peak=NA rms=NA"
    return 1
  fi
  local stat peak rms
  stat="$(sox "$wav" -n stat 2>&1 || true)"
  peak="$(printf '%s\n' "$stat" | awk '/Maximum amplitude:/ {print $3; exit}')"
  rms="$(printf '%s\n' "$stat" | awk '/RMS[[:space:]]+amplitude:/ {print $3; exit}')"
  peak="${peak:-0}"
  rms="${rms:-0}"
  echo "peak=$peak rms=$rms"
  awk "BEGIN{exit !($peak > 0.00001 || $rms > 0.000005)}"
}

install_persistence() {
  local card="$1"

  say "Install persistent DMIC gain fix"
  sudo tee /usr/local/sbin/acer-sf314-dmic-init >/dev/null <<'EOS'
#!/usr/bin/env bash
set -u
for _ in $(seq 1 30); do
  TXT="$(arecord -l 2>/dev/null || true)"
  CARD="$(printf '%s\n' "$TXT" | sed -n 's/^карта \([0-9][0-9]*\): DMIC .*/\1/p' | head -n1)"
  [ -n "$CARD" ] || CARD="$(printf '%s\n' "$TXT" | sed -n 's/^card \([0-9][0-9]*\): DMIC .*/\1/p' | head -n1)"
  if [ -n "$CARD" ]; then
    /usr/bin/amixer -c "$CARD" sset 'DMIC' 100% >/dev/null 2>&1 ||       /usr/bin/amixer -c "$CARD" cset name='DMIC' 2147483647 >/dev/null 2>&1 || true
    exit 0
  fi
  sleep 1
done
exit 1
EOS
  sudo chmod 0755 /usr/local/sbin/acer-sf314-dmic-init

  sudo tee /etc/systemd/system/acer-sf314-dmic-init.service >/dev/null <<'EOS'
[Unit]
Description=Acer Swift SF314 AVS DMIC gain initialization
After=sound.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/acer-sf314-dmic-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOS

  sudo systemctl daemon-reload
  sudo systemctl enable acer-sf314-dmic-init.service
  sudo systemctl restart acer-sf314-dmic-init.service || true

  say "Install persistent PipeWire source selection"
  mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
  cat > "$HOME/.local/bin/acer-sf314-dmic-pipewire-init" <<'EOS'
#!/usr/bin/env bash
set -u
for _ in $(seq 1 30); do
  SOURCE="$(pactl list short sources 2>/dev/null | awk '$2 ~ /avs_dmic/ {print $2; exit}')"
  if [ -n "$SOURCE" ]; then
    pactl set-source-mute "$SOURCE" 0 || true
    pactl set-source-volume "$SOURCE" 100% || true
    pactl set-default-source "$SOURCE" || true
    exit 0
  fi
  sleep 1
done
exit 1
EOS
  chmod 0755 "$HOME/.local/bin/acer-sf314-dmic-pipewire-init"

  cat > "$HOME/.config/systemd/user/acer-sf314-dmic-pipewire.service" <<'EOS'
[Unit]
Description=Select Acer AVS DMIC as PipeWire default source
After=pipewire.service pipewire-pulse.service wireplumber.service
Wants=pipewire.service pipewire-pulse.service wireplumber.service

[Service]
Type=oneshot
ExecStart=%h/.local/bin/acer-sf314-dmic-pipewire-init
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOS

  systemctl --user daemon-reload
  systemctl --user enable acer-sf314-dmic-pipewire.service
  systemctl --user restart acer-sf314-dmic-pipewire.service || true
  ok "Persistent gain and default-source services installed"
}

rollback() {
  say "Rollback persistent DMIC fix"
  sudo systemctl disable --now acer-sf314-dmic-init.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/acer-sf314-dmic-init.service /usr/local/sbin/acer-sf314-dmic-init
  sudo systemctl daemon-reload

  systemctl --user disable --now acer-sf314-dmic-pipewire.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/acer-sf314-dmic-pipewire.service"
  rm -f "$HOME/.local/bin/acer-sf314-dmic-pipewire-init"
  systemctl --user daemon-reload
  ok "Persistence removed. AVS/GRUB/firmware changes are not reverted by this command."
  exit 0
}

[ "$MODE" = "--rollback" ] && rollback

say "Preflight"
echo "Product: $(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
echo "Board:   $(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
echo "Kernel:  $(uname -r)"
echo "Cmdline: $(cat /proc/cmdline)"

if ! grep -qw 'snd_intel_dspcfg.dsp_driver=2' /proc/cmdline; then
  fail "This system is not booted with snd_intel_dspcfg.dsp_driver=2. Run prepare-avs.sh first."
  exit 2
fi

if ! lspci -nnk | grep -A4 -Ei 'audio|multimedia' | grep -q 'Kernel driver in use: snd_soc_avs'; then
  fail "snd_soc_avs is not the active audio driver."
  exit 2
fi

command -v sox >/dev/null 2>&1 || {
  sudo apt-get update
  sudo apt-get install -y sox
}

CARD="$(find_dmic_card)"
if [ -z "$CARD" ]; then
  fail "AVS DMIC card not found."
  arecord -l || true
  exit 3
fi
ok "AVS DMIC card=$CARD"

SOURCE="$(find_dmic_source)"
echo "PipeWire source=${SOURCE:-not-found}"

say "DMIC control before fix"
amixer -c "$CARD" sget 'DMIC' || true

say "Set AVS DMIC gain to 100%"
if ! amixer -c "$CARD" sset 'DMIC' 100%; then
  warn "sset failed; trying raw maximum value"
  amixer -c "$CARD" cset name='DMIC' 2147483647 || true
fi

echo "After:"
amixer -c "$CARD" sget 'DMIC' || true

DIRECT_WAV="$BASE/direct-$STAMP.wav"
say "Direct ALSA capture test: S16_LE / 48000 Hz / stereo"
echo "Speak for 5 seconds..."
if arecord -D "hw:${CARD},0" -f S16_LE -r 48000 -c 2 -d 5 "$DIRECT_WAV"; then
  if wav_stats "$DIRECT_WAV"; then
    ok "Direct ALSA capture contains non-zero audio"
    ALSA_OK=1
  else
    fail "Direct ALSA capture is still digital silence"
    ALSA_OK=0
  fi
else
  fail "Direct ALSA capture command failed"
  ALSA_OK=0
fi

PIPE_OK=0
if [ -n "$SOURCE" ]; then
  say "PipeWire setup and capture test"
  pactl set-source-mute "$SOURCE" 0 || true
  pactl set-source-volume "$SOURCE" 100% || true
  pactl set-default-source "$SOURCE" || true
  echo "Default source: $(pactl get-default-source 2>/dev/null || true)"

  PIPE_WAV="$BASE/pipewire-$STAMP.wav"
  echo "Speak for another 5 seconds..."
  timeout 7 parecord --device="$SOURCE" --file-format=wav "$PIPE_WAV" >/dev/null 2>&1 || true
  if wav_stats "$PIPE_WAV"; then
    ok "PipeWire capture contains non-zero audio"
    PIPE_OK=1
  else
    warn "PipeWire capture is still silent"
  fi
fi

say "Result"
echo "ALSA_OK=$ALSA_OK"
echo "PIPEWIRE_OK=$PIPE_OK"
echo "Log: $LOG"
echo "Direct WAV: $DIRECT_WAV"

if [ "$ALSA_OK" -eq 1 ]; then
  install_persistence "$CARD"
  echo
  ok "Fix applied. Restart Brave/Chrome and test dictation."
  exit 0
fi

fail "DMIC gain was raised, but the hardware stream is still silent."
echo "This points to AVS topology/NHLT compatibility rather than browser or PipeWire configuration."
exit 10
