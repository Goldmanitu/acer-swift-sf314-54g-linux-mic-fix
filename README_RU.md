# Исправление встроенного микрофона Acer Swift SF314-54G в Linux

Рабочее решение для ситуации, когда встроенный цифровой микрофон Acer Swift SF314-54G с Realtek ALC256 и Intel SST/AVS в Linux либо не определяется, либо определяется, но записывает полную тишину.

## Проверенная конфигурация

- Acer Swift SF314-54G
- плата: `Strongbow_KL`
- Intel Sunrise Point-LP HD Audio: `8086:9d71`
- Acer subsystem: `1025:126b`
- кодек: Realtek ALC256
- встроенный микрофон: Intel SST/AVS DMIC
- Zorin OS 18.1 на базе Ubuntu 24.04 Noble
- ядро: `7.0.0-34-generic`
- PipeWire + WirePlumber
- Brave и Google Chrome

## Что происходило

В режиме legacy HDA:

```text
snd_intel_dspcfg.dsp_driver=1
Kernel driver in use: snd_hda_intel
```

Linux видел ALC256 и микрофон гарнитуры, но не настоящий встроенный цифровой микрофон.

После переключения на Intel SST/AVS:

```text
snd_intel_dspcfg.dsp_driver=2
Kernel driver in use: snd_soc_avs
```

сначала не хватало AVS topology-файлов, например:

```text
intel/avs/dmic-tplg.bin failed with error -2
```

После установки topology появился настоящий:

```text
AVS DMIC
Digital Microphone
```

и PipeWire начал показывать источник вида:

```text
alsa_input.platform-avs_dmic.3.auto.stereo-fallback
```

Но запись всё равно состояла только из цифровых нулей.

Аппаратный режим оказался:

```text
S16_LE
48000 Hz
2 channels
```

При этом низкоуровневый регулятор AVS показывал:

```text
Simple mixer control 'DMIC',0
Mono: 0 [0%]
```

а PipeWire показывал 100%.

То есть PipeWire усиливал уже нулевой поток.

Финальный рабочий фикс:

```bash
amixer -c <номер_карты_DMIC> sset 'DMIC' 100%
```

## Автоматическая установка

```bash
git clone https://github.com/Goldmanitu/acer-swift-sf314-54g-linux-mic-fix.git
cd acer-swift-sf314-54g-linux-mic-fix
./install.sh
```

Если AVS ещё не настроен, первый запуск подготовит Intel SST/AVS, firmware/topology и GRUB. После этого потребуется:

```bash
sudo reboot
```

Затем снова:

```bash
cd acer-swift-sf314-54g-linux-mic-fix
./install.sh
```

Второй этап найдёт AVS DMIC, поднимет его внутренний gain до 100%, запишет прямой тест, проверит PipeWire и закрепит настройку через systemd.

## Если AVS DMIC уже есть

Можно сразу запустить:

```bash
./scripts/fix-dmic-gain.sh
```

Проверка:

```bash
arecord -l
pactl list short sources
```

## Откат

Только постоянная настройка gain/default source:

```bash
./scripts/fix-dmic-gain.sh --rollback
```

Возврат к старому HDA-драйверу:

```bash
./scripts/prepare-avs.sh --rollback
sudo reboot
```

## Важно

Решение проверено на конкретном SF314-54G. Не запускайте подготовительный AVS-этап вслепую на другом ноутбуке.

Полное техническое описание, поисковые строки и upstream-ссылки находятся в [README.md](README.md) и [AI_CONTEXT.md](AI_CONTEXT.md).
