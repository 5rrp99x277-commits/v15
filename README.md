# RP2040 CYW4373 Emulator v4_tolerant (без хаба)

Эмулятор Wi-Fi модуля Canon K30387/K30387-2 (Infineon/CYW4373L) на RP2040-Zero.

**Версия v4_tolerant** — исправленная: tolerance, Power Control, правильные endpoint'ы, UART-лог.

## Архитектура

```
Canon Host (3.3V Vbus, D+, D-)
         │
         ▼
    ┌─────────────┐
    │  RP2040     │
    │ 04b4:bd29   │
    │ → 04b4:0bdc │
    └─────────────┘
```

**Важно**: Canon не требует Bluetooth (pin 8 шлейфа на земле). Хаб не используется.

## Исправления в этой версии

| Проблема | Исправление |
|----------|-------------|
| Опечатка `ENDOINT` → `ENDPOINT` | ✅ Исправлено |
| USB Serial включён | ✅ `stdio_usb OFF`, `stdio_uart ON` (GPIO0 TX / GPIO1 RX) |
| Нет ожидания Power Control | ✅ Ждём GPIO2 (WL_REG_ON) HIGH перед стартом USB |
| Неправильные endpoint'ы | ✅ EP81 INT IN, EP82 BULK IN, EP02 BULK OUT (как у реального CYW4373) |
| Ошибка в bulk callback | ✅ `tud_vendor_n_read(itf, ...)` — правильный API TinyUSB |
| Reconnect только по DL_RESETCFG | ✅ + reconnect по DL_GO (если DL_RESETCFG не пришёл) |
| D+/D- в README нечётко | ✅ Строго: Canon D- → RP2040 D-, Canon D+ → RP2040 D+ |

## Пины подключения (строгое соответствие CYW4373)

| Canon шлейф | RP2040 | Функция |
|-------------|--------|---------|
| **Pin 1** | **GPIO2** | Power Control / WL_REG_ON (вход, pull-down) |
| **Pin 2** (3.3V) | **3V3** | Питание |
| **Pin 3,4,7,8** | **GND** | Земля |
| **Pin 5 (D-)** | **USB DM** (pin 19) | USB Data minus |
| **Pin 6 (D+)** | **USB DP** (pin 20) | USB Data plus |

**Важно**: D- и D+ подключать строго 1:1. Менять местами нельзя.

**UART лог** (для отладки): GPIO0 (TX) → USB-TTL RX, GPIO1 (RX) → USB-TTL TX.

## Power Control (WL_REG_ON)

Эмулятор ждёт HIGH на GPIO2 (Canon pin 1 / WL_REG_ON) перед стартом USB. Это соответствует реальному поведению CYW4373: Wi-Fi секция выходит из reset только после активации WL_REG_ON.

Если Canon не управляет pin 1 — подтяните GPIO2 к 3.3V резистором 10K.

## Boot-режим (04b4:bd29)

Принимает Broadcom/Cypress download-команды с tolerant-логикой:
- `DL_GETVER` → bootrom_id (chip=0x4373, ramsize=0xC0000)
- `DL_START` → сброс счётчиков, начало загрузки
- `DL_GETSTATE` → умный: READY/RUNNABLE с fallback по опросам
- `DL_GO` → запуск firmware + планирует reconnect (если DL_RESETCFG не пришёл — reconnect через 500 мс)
- `DL_RESETCFG` → reconnect с PID `04b4:0bdc` (приоритетный путь)

## Runtime-режим (04b4:0bdc)

Отвечает на BCDC/DCMD:
- `cur_etheraddr` → MAC `02:CA:37:03:87:01`
- `ver` → реальная строка из логов CYW4373
- `clmver` → реальная строка CLM
- `event_msgs` → 0xFF (все события включены)
- `mpc` → 1 (multi-processor communication ON)
- `GET_REVINFO` → chipnum = 0x4373

## Tolerance knobs (в `main.c`)

```c
#define CYW4373_ASSUME_DL_START_ON_BULK       1   // bulk без DL_START = авто-старт
#define CYW4373_AUTO_RUNTIME_FALLBACK         1   // переход в runtime без DL_GO
#define CYW4373_AUTO_RUNTIME_FALLBACK_DELAY_MS  1200
#define CYW4373_AUTO_RUNTIME_MIN_BYTES        32768
#define CYW4373_RUNNABLE_FALLBACK_GETSTATE_POLLS 6
#define CYW4373_DL_GO_RECONNECT_DELAY_MS      500  // reconnect после DL_GO
```

## Сборка

```bash
export PICO_SDK_PATH=/path/to/pico-sdk
mkdir build && cd build
cmake ..
make -j
```

Прошивка: `build/cyw4373_emulator_v4_tolerant.uf2`

## Ограничения

- RP2040 — USB Full-Speed 12 Мбит/с
- Если Canon ожидает топологию хаба, используйте версию с USB2512B
- Firmware не сохраняется (нет RAM под 622 KB), только считаются байты

## Checked v4.1 fixes

После проверки добавлены правки:

- добавлен `CFG_TUSB_MCU OPT_MCU_RP2040` в `tusb_config.h`;
- исправлен auto-runtime fallback: reconnect теперь выполняется в `boot_mode`;
- UART инициализируется явно: `GPIO0 TX`, `GPIO1 RX`, `115200`;
- `EP81 interrupt IN` сделан ближе к реальным логам: `MxPS=16`, interval `16`.

Это всё ещё no-hub версия: `04b4:bd29 -> 04b4:0bdc`, без настоящего `04b4:bd30`.


## v4.2 update — vendor device class

Changed both boot and runtime USB device descriptors:

```c
.bDeviceClass = 0xFF
```

This applies to:

- `04b4:bd29` Remote Download Wireless Adapter
- `04b4:0bdc` Cypress USB 802.11 Wireless Adapter

Why:

- Broadcom/Cypress USB Wi-Fi devices are vendor-specific.
- brcmfmac checks for vendor-specific device/interface in several USB paths.
- Interface remains `FF / 02 / FF`.
- Endpoint layout remains `EP81 interrupt IN`, `EP82 bulk IN`, `EP02 bulk OUT`.

Expected UF2 after build:

```text
cyw4373_emulator_nohub_checked_v4_2.uf2
```


## v4.3 final code-check fixes

After reviewing the whole code against the current TZ, v4.3 changes:

- keeps `bDeviceClass = 0xFF` for both `04b4:bd29` and `04b4:0bdc`;
- endpoint set is unchanged, but descriptor order is changed for TinyUSB compatibility:
  - `EP02 bulk OUT`
  - `EP82 bulk IN`
  - `EP81 interrupt IN`
- waits for `WL_REG_ON / Power Control` indefinitely by default;
  - for bench testing, tie `GPIO2` to `3.3V`;
- accepts `DL_*` requests by command even if `wLength` differs slightly;
- unknown boot vendor-IN requests return zero success instead of stalling;
- runtime BCDC/DCMD OUT is parsed on either DATA or ACK stage, only once;
- added explicit logs for `DL_GETVER`, runtime OUT, and `cur_etheraddr`;
- uses `board_init(); tusb_init();` instead of direct rhport macro dependency.

Expected UF2 after build:

```text
cyw4373_emulator_nohub_checked_v4_3.uf2
```


## v4.4 protocol clarification / safety update

Important correction:

- `DL_GETSTATE` response is **8 bytes only**:
  - `u32 state`
  - `u32 bytes`
- `chip=0x4373` is returned by `DL_GETVER`, not by `DL_GETSTATE`.
- `DL_GETVER` response is **24 bytes** `bootrom_id_le`.

Added safe handlers for less common download commands:

- `DL_CHECK_CRC`
- `DL_GO_PROTECTED`
- `DL_EXEC`

These commands are normally not required for the CYW4373 firmware download path, but handling them prevents unnecessary stalls if Canon probes them.

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_4.uf2
```


## v4.5 real-log descriptor update

Changes based on real CYW4373 USB logs:

- `bcdDevice = 0x0001` for both boot and runtime device descriptors.
- Boot product string changed to:
  - `Remote Download Wireless Adapter\x01`
- Runtime product string remains:
  - `Cypress USB 802.11 Wireless Adapter`
- Manufacturer remains:
  - `Cypress Semiconductor Corp.`
- Serial remains:
  - `000000000001`
- Endpoint set remains:
  - `EP81 interrupt IN`
  - `EP82 bulk IN`
  - `EP02 bulk OUT`
- `bDeviceClass = 0xFF` remains.
- Interface remains `FF / 02 / FF`.
- `DL_GETSTATE` remains the correct 8-byte structure:
  - `u32 state`
  - `u32 bytes`
- `DL_GETVER` remains the 24-byte structure carrying `chip=0x4373`.

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_5.uf2
```

Note:

The `\x01` at the end of the boot product string is included because one real Linux log printed:
`Product: Remote Download Wireless Adapter\x01`.
If Canon dislikes this exact string, revert it to `Remote Download Wireless Adapter`.


## v4.6 final audit update

Critical fix after checking `brcmfmac/usb.c` probe logic:

- Endpoint **order** in the interface descriptor is now:
  1. `EP81 interrupt IN`
  2. `EP82 bulk IN`
  3. `EP02 bulk OUT`

Why this matters:

- `brcmfmac` checks endpoint index 0 and requires it to be interrupt.
- Bulk endpoints are scanned starting from endpoint index 1.
- v4.5 had the right endpoint set but could have the wrong order.

Still kept:

- `bDeviceClass = 0xFF`
- interface `FF / 02 / FF`
- `bcdDevice = 0x0001`
- boot string `Remote Download Wireless Adapter\x01`
- runtime string `Cypress USB 802.11 Wireless Adapter`
- `DL_GETSTATE` = 8 bytes `state + bytes`
- `DL_GETVER` = 24 bytes, returns chip `0x4373`
- runtime control:
  - OUT `0x21 bRequest=0`
  - IN `0xA1 bRequest=1`

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_6.uf2
```


## v4.7 NVRAM/OTP fallback update

Added runtime fallback answers for possible Canon/driver board identity queries.

NVRAM-like values:

```text
manfid=0x2d0
prodid=0x4373
sromrev=11
macaddr=02:CA:37:03:87:01
boardrev=0x1301
boardnum=9492
boardtype=0x83d
customvar1=0x222d0000
aa2g=3
aa5g=3
devid=0x4418
nocrc=1
vendid=0x14e4
```

New supported `GET_VAR` names:

- `manfid`
- `prodid`
- `sromrev`
- `boardrev`
- `boardnum`
- `boardtype`
- `devid`
- `vendid`
- `macaddr`
- `vars`
- `nvram`
- `nvram_dump`
- `cisdump`
- `otpdump`

Important:

This does not mean the emulator runs real CYW4373 firmware or consumes NVRAM.
It only returns plausible values if the host asks for them in runtime BCDC/DCMD.

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_7.uf2
```


## v4.8 RP2040-safe descriptor update

Updated from real CYW4373 endpoint/config observations, but kept valid Full-Speed limits for RP2040.

Changed:

- `bMaxPower = 0xFA` = 500 mA
- `EP81 interrupt IN bInterval = 9`
- endpoint order remains:
  1. `EP81 interrupt IN`
  2. `EP82 bulk IN`
  3. `EP02 bulk OUT`

Important RP2040 limitation:

Real CYW4373 High-Speed descriptors use bulk `wMaxPacketSize = 512`.
RP2040 is USB Full-Speed only, so bulk endpoints must stay `64`.
Setting `512` on RP2040 Full-Speed can break enumeration.

For a future STM32H7+USB3300 / Teensy / Cynthion High-Speed version:

```c
Bulk IN  wMaxPacketSize = 512
Bulk OUT wMaxPacketSize = 512
```

For this RP2040 no-hub build:

```c
Bulk IN  wMaxPacketSize = 64
Bulk OUT wMaxPacketSize = 64
```

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_8.uf2
```


## v4.9 final checked update

This build was checked against the accumulated CYW4373 USB findings.

Critical final fixes:

1. Removed `tud_task()` before `tusb_init()` while waiting for `WL_REG_ON`.
2. `DL_GETSTATE` is explicitly kept as a fast control-IN response through `tud_control_xfer()`.
3. If Canon asks `DL_GETSTATE` before `DL_START`, the emulator now returns `DL_READY` instead of staying `DL_WAITING`.
4. `DL_GETVER` remains the fast 24-byte chip-ID response:
   - boot chip `0x4373`
   - postboot chip `0xA123`
5. RP2040-safe descriptors are kept:
   - Full-Speed bulk MPS `64`, not `512`
   - `bMaxPower = 0xFA`
   - `bDeviceClass = 0xFF`
   - interface `FF/02/FF`
   - endpoint order `EP81 interrupt`, `EP82 bulk IN`, `EP02 bulk OUT`.

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_9.uf2
```


## v4.10 real NVRAM / OTP tuple update

Added real Murata 2AE / CYW4373-style NVRAM values and OTP MAC tuple fallback.

NVRAM text now includes:

```text
manfid=0x2d0
prodid=0x4373
sromrev=11
macaddr=02:CA:37:03:87:01
boardrev=0x1301
boardnum=9492
boardtype=0x83d
customvar1=0x222d0000
aa2g=3
aa5g=3
devid=0x4418
nocrc=1
vendid=0x14e4
pa2ga0=-188,5529,-658
pa5ga0=-153,5976,-697,-153,5784,-684,-155,5691,-677,-167,5748,-688
```

Added MAC OTP tuple fallback:

```c
80 07 19 02 CA 37 03 87 01
```

New supported runtime `GET_VAR` names:

- `nocrc`
- `aa2g`
- `aa5g`
- `mac_otp_tuple`
- `otp_mac_tuple`

Still RP2040-safe:

- Real High-Speed CYW4373 bulk MPS is `512`.
- RP2040 Full-Speed bulk MPS must remain `64`.
- This build keeps `64`.

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_10.uf2
```


## v4.11 final descriptor correction

Updated based on the final brcmfmac descriptor checks and real CYW4373 observations.

Changed:

- `bMaxPower = 0x32` = 100 mA.

Confirmed / kept:

- `bNumConfigurations = 1`
- `bDeviceClass = 0xFF`
- `bNumInterfaces = 1`
- `bInterfaceClass = 0xFF`
- `bInterfaceSubClass = 0x02`
- `bInterfaceProtocol = 0xFF`
- endpoint order:
  1. `EP81 interrupt IN`
  2. `EP82 bulk IN`
  3. `EP02 bulk OUT`
- `EP81 wMaxPacketSize = 16`
- `EP81 bInterval = 9`
- `DL_GETSTATE` fast response via `tud_control_xfer()`
- `DL_GETVER` fast response with chip `0x4373`
- runtime BCDC:
  - OUT `0x21 bRequest=0`
  - IN `0xA1 bRequest=1`

Important RP2040 limitation:

Real CYW4373 High-Speed bulk endpoints use `wMaxPacketSize = 512`.
This RP2040 build is Full-Speed, so bulk endpoints must remain `64`.

Do not change bulk MPS to `512` in the RP2040 build.

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_11.uf2
```


## v4.12 LED indicator update

Added status indication for Waveshare RP2040-Zero:

- Onboard WS2812/RGB LED: `GPIO16`
- Optional external/simple LED output: `GPIO25`

LED states:

```text
OFF      = waiting for WL_REG_ON / Power Control
YELLOW   = WL_REG_ON active, stable delay is running
BLUE     = USB boot mode 04b4:bd29 active
PURPLE   = DL_GETVER / DL_START activity seen
GREEN    = runtime mode 04b4:0bdc active
RED      = reserved for future error indication
```

This helps verify that the plotter really raises `WL_REG_ON` and that the emulator waits before USB attach.

Connection reminder:

```text
Plotter pin 1 Power Control / WL_REG_ON -> RP2040 GPIO2
RP2040 onboard RGB LED is GPIO16
UART log remains GPIO0 TX, 115200
```

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_12.uf2
```


## v4.13 final LED fixed audit

Critical fixes after code inspection:

1. Fixed invalid C string literals in `CYW4373_NVRAM_TEXT`.
   - The previous LED build could fail compilation because newline characters were inserted inside quoted strings.
2. Replaced `tud_vendor_rx_cb()` firmware reception with polling:
   - `tud_vendor_available()`
   - `tud_vendor_read()`
   This avoids TinyUSB callback signature differences across Pico SDK versions.
3. Added `hardware_sync` explicitly for `save_and_disable_interrupts()` used by the WS2812 LED bit-bang code.

Kept from v4.12:

- WS2812 status LED on GPIO16
- optional simple LED output on GPIO25
- UART on GPIO0, 115200
- WL_REG_ON / Power Control on GPIO2
- `04b4:bd29 -> 04b4:0bdc`
- `bDeviceClass = 0xFF`
- interface `FF/02/FF`
- endpoint order `EP81 interrupt`, `EP82 bulk IN`, `EP02 bulk OUT`
- Full-Speed bulk MPS `64`, correct for RP2040

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_13.uf2
```


## v4.14 final LED audited

Final strict code audit fixes:

1. Fixed broken `printf()` string literals in bulk polling.
   - Previous v4.13 still had real newline characters inside quoted strings in three `printf()` calls.
   - That would cause C compilation errors.
2. Fixed NVRAM text encoding.
   - Now C source contains normal `\n` escapes, so runtime NVRAM text contains real newline separators.
3. Kept bulk firmware reception in polling mode:
   - `tud_vendor_available()`
   - `tud_vendor_read()`
4. Kept LED indicator:
   - WS2812 GPIO16
   - external/simple LED GPIO25
5. Kept final USB/TZ values:
   - `04b4:bd29 -> 04b4:0bdc`
   - `bDeviceClass = 0xFF`
   - interface `FF/02/FF`
   - endpoint order `EP81 interrupt`, `EP82 bulk IN`, `EP02 bulk OUT`
   - RP2040 Full-Speed bulk MPS `64`
   - `bMaxPower = 0x32`
   - `DL_GETSTATE` fast 8-byte response
   - `DL_GETVER` fast 24-byte response with chip `0x4373`

Expected UF2:

```text
cyw4373_emulator_nohub_checked_v4_14.uf2
```

# Build UF2 through GitHub Actions

This archive includes a ready workflow:

```text
.github/workflows/build-uf2.yml
```

How to build online:

1. Create a new GitHub repository.
2. Upload all files from this archive to the repository root.
3. Open GitHub → Actions.
4. Select `Build RP2040 CYW4373 Emulator UF2`.
5. Press `Run workflow`.
6. Download the artifact:
   `cyw4373_emulator_nohub_checked_v4_14_uf2`.

Expected UF2 name after build:

```text
cyw4373_emulator_nohub_checked_v4_14.uf2
```

Important test wiring:

```text
Plotter pin 1 Power Control / WL_REG_ON -> RP2040 GPIO2
UART log TX -> RP2040 GPIO0, 115200 8N1
Onboard RGB LED -> GPIO16
Optional external LED -> GPIO25
```

# v4.15 Fast attach test

This version is based on v4.14 but changes the WL_REG_ON stable delay:

```text
v4.14: 2000 ms
v4.15: 200 ms
```

Reason:

The UART log showed:

```text
WL_REG_ON active
TinyUSB started
```

but did not show:

```text
USB mounted as boot 04b4:bd29
BOOT DL_GETVER
```

So the plotter raised Power Control and the emulator started, but the host did not complete USB enumeration. One possible cause is that the emulator appeared too late after WL_REG_ON. This build tests faster USB attach timing.

Expected next UART result to look for:

```text
USB mounted as boot 04b4:bd29
BOOT DL_GETVER
```
