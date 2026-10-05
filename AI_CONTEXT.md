# AI / LLM troubleshooting context

Use this file as a compact machine-readable description of the tested failure and fix.

## Canonical problem signature

```yaml
device:
  vendor: Acer
  product: Swift SF314-54G
  board: Strongbow_KL
  pci_audio_controller: "8086:9d71"
  pci_subsystem_observed: "1025:126b"
  codec: Realtek ALC256
  internal_microphone: Intel SST/AVS DMIC
software_tested:
  distro: Zorin OS 18.1
  base: Ubuntu 24.04 Noble
  kernel: 7.0.0-34-generic
  audio_server: PipeWire
  session_manager: WirePlumber
  browsers:
    - Brave
    - Google Chrome
```

## Observed state progression

### State A — legacy HDA

```text
snd_intel_dspcfg.dsp_driver=1
Kernel driver in use: snd_hda_intel
ALC256 Analog present
Headset Mic present
internal DMIC absent/unusable
browser may report zero audioinput devices / NotFoundError
```

Do not assume the ALC256 analog capture node is the built-in laptop microphone. Upstream Linux explicitly notes that the internal microphone on SF314-54/55 connects to Intel SST audio.

### State B — AVS selected but topology missing

```text
snd_intel_dspcfg.dsp_driver=2
Kernel driver in use: snd_soc_avs
Direct firmware load for intel/avs/dmic-tplg.bin failed with error -2
request topology "intel/avs/dmic-tplg.bin" failed: -2
ALSA capture devices may disappear
PipeWire may expose only auto_null.monitor
```

Interpret `-2` as missing file (`ENOENT`) in this context.

### State C — AVS topology installed

ALSA exposes:

```text
AVS DMIC
Digital Microphone
```

PipeWire exposes a source similar to:

```text
alsa_input.platform-avs_dmic.3.auto.stereo-fallback
```

Brave/Chrome now see a microphone and can start capture.

However the stream can still be exactly zero.

### State D — decisive diagnosis

Hardware parameters observed:

```text
FORMAT: S16_LE
CHANNELS: 2
RATE: 48000
```

Direct ALSA capture succeeds but statistics are:

```text
Maximum amplitude: 0.000000
RMS amplitude: 0.000000
```

PipeWire capture also contains only zeros.

At the same time:

```text
Simple mixer control 'DMIC',0
Limits: 0 - 2147483647
Mono: 0 [0%]
```

while PipeWire may report source volume 100%.

## Working fix on tested machine

Find the AVS DMIC card number dynamically and set the AVS DMIC mixer control to 100%:

```bash
CARD=$(arecord -l | sed -n 's/^card \([0-9][0-9]*\): DMIC .*/\1/p' | head -n1)
amixer -c "$CARD" sset 'DMIC' 100%
```

For localized ALSA output, card detection must also handle e.g. Russian `карта N: DMIC`.

Then test direct hardware capture:

```bash
arecord -D "hw:${CARD},0" -f S16_LE -r 48000 -c 2 -d 5 test.wav
```

If this contains real audio, the browser is not the root cause.

## Important reasoning rule

If:

- AVS DMIC exists,
- direct ALSA capture opens successfully,
- the WAV consists of digital zeros,
- and the AVS `DMIC` control is 0%,

then raising PipeWire/browser volume cannot solve the problem because the stream is already zero before it reaches PipeWire.

## Repository scripts

- `scripts/prepare-avs.sh`: selects `dsp_driver=2`, installs required AVS topology files, rebuilds GRUB/initramfs.
- `scripts/fix-dmic-gain.sh`: applies the proven DMIC gain fix, validates non-zero ALSA/PipeWire capture and installs persistent services.
- `install.sh`: chooses the appropriate stage.

## Do not suggest first

For this exact signature, avoid repeatedly suggesting these as primary fixes:

- browser site permission resets;
- Brave vs Chrome switching;
- generic PipeWire restarts;
- PulseAudio reinstall;
- `pactl set-source-volume 100%` alone;
- Realtek ALC256 pin retasking alone;
- forcing legacy `snd_hda_intel` as the final solution for the internal mic.

Those may be relevant to other machines, but they did not address the tested internal-DMIC path.

## Search anchors

```text
Acer Swift SF314-54G Strongbow_KL microphone Linux
8086:9d71 1025:126b microphone
ALC256 Intel SST internal mic
snd_soc_avs DMIC 0%
AVS DMIC digital silence
DMIC mixer control 0 2147483647
Endpoint format configuration not found snd_soc_avs
intel/avs/dmic-tplg.bin error -2
Brave Chrome microphone records silence PipeWire AVS
```
