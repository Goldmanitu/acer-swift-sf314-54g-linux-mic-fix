---
name: Bug report / unsupported variant
about: Report a failure or a similar Acer Swift audio configuration
title: "[audio] "
labels: ""
assignees: ""
---

## Laptop

```bash
cat /sys/class/dmi/id/sys_vendor
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/board_name
```

## Kernel / distro

```bash
uname -a
cat /etc/os-release
```

## Audio PCI device

```bash
lspci -nnk | grep -A4 -Ei 'audio|multimedia'
```

## DSP mode

```bash
cat /proc/cmdline
cat /sys/module/snd_intel_dspcfg/parameters/dsp_driver 2>/dev/null
```

## ALSA capture devices

```bash
arecord -l
```

## DMIC control

```bash
amixer -c 0 scontents
amixer -c 1 scontents
amixer -c 2 scontents
```

## PipeWire sources

```bash
pactl list short sources
pactl get-default-source
```

## Relevant kernel log

```bash
journalctl -b -k --no-pager | grep -Ei 'snd|avs|sst|dmic|hda|topology|NHLT'
```

## What happened

Describe what you expected and what happened instead.
