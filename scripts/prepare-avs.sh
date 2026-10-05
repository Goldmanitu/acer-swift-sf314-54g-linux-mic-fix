#!/usr/bin/env bash
set -euo pipefail

TAG="20260916"
FW_BASE="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/${TAG}/intel/avs"
DEST="/lib/firmware/intel/avs"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/var/backups/acer-sf314-avs-$STAMP"
MODE="${1:-apply}"

say(){ printf '\n=== %s ===\n' "$*"; }
ok(){ printf '[OK] %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*"; }
die(){ printf '[ERROR] %s\n' "$*"; exit 1; }

if [ "$MODE" = "--rollback" ]; then
  say "Rollback to legacy HDA"
  sudo -v
  if grep -q 'snd_intel_dspcfg.dsp_driver=2' /etc/default/grub 2>/dev/null; then
    sudo sed -i 's/snd_intel_dspcfg\.dsp_driver=2/snd_intel_dspcfg.dsp_driver=1/g' /etc/default/grub
  fi
  sudo rm -f /etc/modprobe.d/zz-acer-sf314-mic-sst.conf
  sudo update-grub
  sudo update-initramfs -u
  ok "Boot mode set back to dsp_driver=1. Reboot required."
  exit 0
fi

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
AUDIO="$(lspci -nnk | grep -A4 -Ei 'audio|multimedia' || true)"

say "Hardware check"
echo "Vendor:  $VENDOR"
echo "Product: $PRODUCT"
echo "$AUDIO"

if ! echo "$VENDOR $PRODUCT" | grep -qiE 'Acer.*SF314-54'; then
  die "This installer is intentionally restricted to Acer Swift SF314-54 family."
fi

if ! echo "$AUDIO" | grep -q '8086:9d71'; then
  die "Expected Intel Sunrise Point-LP audio controller 8086:9d71 was not found."
fi

sudo -v
sudo mkdir -p "$BACKUP"
sudo cp -a /etc/default/grub "$BACKUP/grub" 2>/dev/null || true
[ -d "$DEST" ] && sudo cp -a "$DEST" "$BACKUP/avs" || true
ok "Backup: $BACKUP"

say "Install prerequisites"
sudo apt-get update
sudo apt-get install -y curl alsa-utils alsa-ucm-conf alsa-topology-conf linux-firmware pipewire pipewire-pulse wireplumber

say "Force Intel SST/AVS path (dsp_driver=2)"
if grep -q 'snd_intel_dspcfg.dsp_driver=' /etc/default/grub; then
  sudo sed -i -E 's/snd_intel_dspcfg\.dsp_driver=[0-9]+/snd_intel_dspcfg.dsp_driver=2/g' /etc/default/grub
else
  sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")([^"]*)"/\1\2 snd_intel_dspcfg.dsp_driver=2"/' /etc/default/grub
fi

sudo tee /etc/modprobe.d/zz-acer-sf314-mic-sst.conf >/dev/null <<'EOM'
# Acer Swift SF314-54 internal DMIC workaround
# 0=auto, 1=legacy HDA, 2=Intel SST/AVS, 3=SOF
options snd-intel-dspcfg dsp_driver=2
EOM

grep -n 'GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub || true

say "Install AVS topology files from upstream linux-firmware ${TAG}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  local name="$1"
  curl -fL --retry 3 --connect-timeout 20 -o "$TMP/$name" "$FW_BASE/$name"
  [ -s "$TMP/$name" ] || die "Downloaded file is empty: $name"
  sha256sum "$TMP/$name"
}

fetch dmic-tplg.bin
fetch hda-generic-1ep-tplg.bin
fetch hda-808628xx-3ep-tplg.bin

sudo mkdir -p "$DEST"
sudo install -m 0644 "$TMP/dmic-tplg.bin" "$DEST/dmic-tplg.bin"
sudo install -m 0644 "$TMP/hda-generic-1ep-tplg.bin" "$DEST/hda-generic-1ep-tplg.bin"
sudo install -m 0644 "$TMP/hda-808628xx-3ep-tplg.bin" "$DEST/hda-808628xx-3ep-tplg.bin"
sudo ln -sfn hda-generic-1ep-tplg.bin "$DEST/hda-generic-tplg.bin"
sudo ln -sfn hda-808628xx-3ep-tplg.bin "$DEST/hda-8086-generic-tplg.bin"

say "Rebuild boot files"
sudo update-grub
sudo update-initramfs -u

cat <<EOM

Preparation complete.

Reboot:
  sudo reboot

After reboot verify that:
  cat /sys/module/snd_intel_dspcfg/parameters/dsp_driver
prints 2, and:
  arecord -l
contains "AVS DMIC" / "Digital Microphone".

Then run:
  ./scripts/fix-dmic-gain.sh

Rollback boot mode if audio is worse:
  ./scripts/prepare-avs.sh --rollback
  sudo reboot

Backup: $BACKUP
EOM
