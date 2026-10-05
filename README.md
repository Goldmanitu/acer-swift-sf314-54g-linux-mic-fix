# Acer Swift SF314-54G Linux internal microphone fix

**Working fix for a silent internal digital microphone (DMIC) on Acer Swift SF314-54G with Realtek ALC256 + Intel SST/AVS on Linux.**

This repository documents and automates a fix for a specific failure mode where:

- the internal microphone is missing or unusable with legacy `snd_hda_intel`;
- Brave/Chrome may initially report no microphone at all;
- after switching to Intel SST/AVS, the browser sees a microphone but records silence;
- `arecord` can open the AVS DMIC successfully, but the WAV file contains only digital zeros;
- the AVS `DMIC` mixer control is exposed at **0%**, while PipeWire may misleadingly show the source at 100%.

On the tested machine, setting the low-level AVS DMIC control to 100% immediately restored real microphone capture.

> **Scope:** tested on one Acer Swift SF314-54G. Do not apply blindly to unrelated laptops.

## Tested hardware and software

| Item | Tested value |
|---|---|
| Laptop | Acer Swift SF314-54G |
| Mainboard | `Strongbow_KL` |
| Audio controller | Intel Sunrise Point-LP HD Audio `8086:9d71` |
| PCI subsystem observed | Acer `1025:126b` |
| HDA codec | Realtek ALC256 |
| Internal mic path | Intel SST/AVS DMIC |
| OS | Zorin OS 18.1 / Ubuntu 24.04 Noble base |
| Kernel | `7.0.0-34-generic` |
| Audio userspace | ALSA + PipeWire + WirePlumber |
| Browsers tested | Brave and Google Chrome |

## Why this happens

The Linux kernel already contains an Acer Swift SF314-54/55 ALC256 quirk. The upstream patch explicitly notes that the **internal microphone is connected to Intel SST audio, not directly to the Realtek HDA codec**.

On the tested installation, the complete failure chain was:

1. Legacy HDA (`snd_hda_intel`, `dsp_driver=1`) exposed the ALC256 analog path and headset mic, but not the real internal DMIC.
2. Switching to Intel SST/AVS (`dsp_driver=2`) selected `snd_soc_avs`.
3. The installed Ubuntu/Zorin firmware set was missing AVS topology files such as `intel/avs/dmic-tplg.bin`, so the AVS cards could not instantiate correctly.
4. After installing current AVS topology files, ALSA exposed:

   ```text
   AVS DMIC / Digital Microphone
   ```

   and PipeWire exposed a source similar to:

   ```text
   alsa_input.platform-avs_dmic.3.auto.stereo-fallback
   ```

5. Direct hardware capture was accepted only as:

   ```text
   S16_LE / 48000 Hz / 2 channels
   ```

   but the resulting audio was all zeros.
6. The decisive finding was:

   ```text
   Simple mixer control 'DMIC',0
   Mono: 0 [0%]
   ```

   while PipeWire itself showed the microphone source at 100%.
7. Raising the **AVS DMIC topology control** to 100% restored capture.

In short: **PipeWire was amplifying a stream that had already been zeroed at the AVS/DMIC control layer.**

## Quick install

Clone the repository and run:

```bash
git clone https://github.com/Goldmanitu/acer-swift-sf314-54g-linux-mic-fix.git
cd acer-swift-sf314-54g-linux-mic-fix
./install.sh
```

The installer is staged.

### Stage 1 — only if AVS DMIC is not active yet

`install.sh` runs `scripts/prepare-avs.sh`, which:

- checks that the machine is an Acer Swift SF314-54 family device with Intel audio controller `8086:9d71`;
- backs up `/etc/default/grub` and the existing AVS firmware directory;
- switches the Intel audio DSP selection to:

  ```text
  snd_intel_dspcfg.dsp_driver=2
  ```

- installs the required Linux audio packages;
- downloads only the required Intel AVS topology files from the upstream `linux-firmware` project;
- rebuilds GRUB and initramfs.

Then reboot:

```bash
sudo reboot
```

After reboot, run the installer again:

```bash
cd acer-swift-sf314-54g-linux-mic-fix
./install.sh
```

### Stage 2 — final working fix

When `AVS DMIC` is present, the installer runs `scripts/fix-dmic-gain.sh`.

It:

1. verifies `dsp_driver=2` and `snd_soc_avs`;
2. locates the AVS DMIC ALSA card dynamically;
3. reads the low-level `DMIC` mixer control;
4. sets it to 100%;
5. records a direct ALSA test at `S16_LE / 48000 Hz / stereo`;
6. verifies that the WAV contains non-zero samples;
7. selects the AVS DMIC as the PipeWire default source;
8. verifies PipeWire capture;
9. installs small systemd services so the gain and default source survive reboot.

Restart Brave/Chrome after a successful run.

## The essential one-line fix

If your system **already has a working `AVS DMIC` card** and the only problem is digital silence, the important command is typically:

```bash
amixer -c <DMIC_CARD_NUMBER> sset 'DMIC' 100%
```

Find the card number with:

```bash
arecord -l
```

Example:

```text
card 1: DMIC [AVS DMIC], device 0: Digital Microphone
```

then:

```bash
amixer -c 1 sset 'DMIC' 100%
```

The repository script avoids hard-coding the card number because it can change between boots.

## Verify the fix

Check ALSA:

```bash
arecord -l
```

Expected to include:

```text
AVS DMIC
Digital Microphone
```

Check the DMIC control:

```bash
CARD=$(arecord -l | sed -n 's/^card \([0-9][0-9]*\): DMIC .*/\1/p' | head -n1)
amixer -c "$CARD" sget 'DMIC'
```

Check PipeWire:

```bash
pactl list short sources
pactl get-default-source
```

Direct capture test:

```bash
arecord -D "hw:${CARD},0" -f S16_LE -r 48000 -c 2 -d 5 test.wav
aplay test.wav
```

## Rollback

Remove only the persistent DMIC gain/default-source fix:

```bash
./scripts/fix-dmic-gain.sh --rollback
```

Return to legacy HDA (`dsp_driver=1`):

```bash
./scripts/prepare-avs.sh --rollback
sudo reboot
```

Backups created by `prepare-avs.sh` are stored under:

```text
/var/backups/acer-sf314-avs-<timestamp>
```

## Important safety notes

- This changes the kernel audio-driver selection and GRUB configuration during Stage 1.
- A wrong DSP-driver choice can temporarily remove audio devices until rollback.
- The scripts intentionally refuse to run Stage 1 on obviously different hardware.
- AVS topology binaries are downloaded from upstream `linux-firmware`; they are not redistributed in this repository.
- The scripts are MIT licensed; upstream firmware keeps its own upstream licensing.

## Useful error strings / search terms

This section is intentionally explicit so GitHub search, web search and AI systems can match the problem.

```text
Acer Swift SF314-54G microphone Linux
Acer Swift 3 SF314-54G internal microphone not working Linux
Realtek ALC256 internal microphone Linux
Intel Sunrise Point-LP HD Audio 8086:9d71 Acer 1025:126b
Strongbow_KL Linux microphone
snd_hda_intel Headset Mic only internal microphone missing
snd_intel_dspcfg.dsp_driver=2
snd_soc_avs Acer Swift
AVS DMIC Digital Microphone
alsa_input.platform-avs_dmic.3.auto.stereo-fallback
Brave microphone NotFoundError Linux
Chrome microphone records silence Linux
PipeWire microphone 100% but silence
DMIC 0% amixer snd_soc_avs
Endpoint format configuration not found snd_soc_avs
intel/avs/dmic-tplg.bin failed with error -2
request topology intel/avs/dmic-tplg.bin failed -2
AVS DMIC S16_LE 48000 stereo silence
```

## Upstream references

- Linux kernel commit for Acer Swift SF314-54/55 + ALC256: the commit explicitly states that the internal microphone connects to Intel SST audio:  
  https://gbmc.googlesource.com/linux/+/d0e185616a0331c87ce3aa1d7dfde8df39d6d002
- Original kernel mailing-list patch:  
  https://lore.kernel.org/r/20210226010440.8474-1-chris.chiu@canonical.com
- `linux-firmware`: AVS Digital Microphone Array topology was added in 2024, based on an AVS topology update that exposed volume control:  
  https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git/+/f1be21917931961aeedd6fce334e725862f76145
- A later upstream update fixed DMIC topology compatibility on some kernels:  
  https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git/+/a32d5cc1a182b83f26a63adfae78853db2e0d151
- Upstream firmware source used by the preparation script:  
  https://gitlab.com/kernel-firmware/linux-firmware

## AI assistants

If you are an AI assistant troubleshooting a similar machine, read [`AI_CONTEXT.md`](AI_CONTEXT.md) before suggesting generic browser permissions, PulseAudio reinstallations or Realtek HDA pin retasking. The tested failure was below the browser and PipeWire layers.

## License

Scripts and documentation in this repository are released under the MIT License. See [`LICENSE`](LICENSE).
