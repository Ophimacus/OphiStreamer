# Milestone 0: hardware proof

Target: **Acer Nitro 5 AN515-52, Windows 11** (usually an Intel Wireless-AC 9560) + **Honor X7d** running Moonlight + GameSir controller.

Two modes (see PLAN.md):
- **Phone hotspot (default, Mode A):** the Honor hosts a 5 GHz hotspot and the laptop joins it.
- **Laptop hotspot (Mode B):** the laptop hosts. Intel cards need the 5 GHz "trigger" first (join a 5 GHz network briefly).

## Before you start
1. Copy this `m0` folder to the laptop.
2. Phone: **Settings → Mobile network → Personal hotspot → More → AP band → 5 GHz** (turn the hotspot off before changing it). Turn off any "turn off hotspot automatically" option. Mobile data can stay **off**.
3. Have **Moonlight** (Play Store) and the **OphiStreamer Link Check** app on the phone, and Sunshine on the laptop.

## Setup checklist (affects the results)

**Laptop**
- Plugged into the charger, power mode **Best performance**.
- Power Options → advanced → **Wireless Adapter Settings → Power Saving Mode: Maximum Performance** (on AC).
- Device Manager → Intel Wireless-AC 9560 → Advanced: **Roaming Aggressiveness: Lowest**, **MIMO Power Save Mode: No SMPS**, **U-APSD: Disabled**, **Packet Coalescing: Disabled**, **Preferred Band: 5 GHz**.
- Latest Intel Wi-Fi driver from intel.com (Acer's is old).
- Lid open (antennas are in the screen bezel).

**Phone (Honor X7d)**
- Battery: power saving **off**; Moonlight set to **no battery restrictions** (Settings → Apps → Moonlight → Battery).
- Moonlight: **1280×720 at 60 fps**, **H.265 (HEVC)**, bitrate **10 Mbps** to start, frame pacing **lowest latency**, **performance overlay on**, on-screen controls off.
- Controller: plug in the GameSir and turn on **OTG** (Settings → search "OTG"). Link Check shows live button input.

**Sunshine**
- Check the Sunshine log says it's using **NVENC** (the NVIDIA GPU), not the Intel iGPU.
- **ViGEmBus** installed so the controller reaches games. The test checks this.

## One-click run (recommended)
1. Phone: turn the hotspot on (band already set to 5 GHz).
2. Laptop, in a normal PowerShell window (not admin), paste:
   ```
   irm https://raw.githubusercontent.com/Ophimacus/OphiStreamer/main/tests/m0/get.ps1 | iex
   ```
   It downloads the latest kit to `%USERPROFILE%\OphiStreamer-m0` and opens the **Test Kit** window. Next time, just double-click **`Start-Test.cmd`** in that folder (`Start-Test-Console.cmd` is the text version).
3. In the window: hotspot name and password (first time only) → **START TEST** → approve one admin prompt (first time only). Steps turn green/amber/red live; when asked, stream with Moonlight and answer with the buttons.
4. Phone: open **Link Check** → **Run link test** → **Copy report**. Send back the `m0-report-*.txt`, the `m0-link-*.csv` and the Link Check report.

**Connection log:** from the moment the phone link is up, the test records the Wi-Fi link every second to `m0-link-*.csv` (state, SSID, band, channel, signal, receive/transmit rate, ping to the phone). The report summarises it as "Connection stayed up": any disconnect or channel change is a FAIL, lost pings a WARN.

If Windows hides the Wi-Fi name (Windows 11 24H2+), turn on Settings → Privacy & security → Location → **Let desktop apps access your location**.

## Manual run (phone hotspot)
1. Turn on the phone hotspot and connect the laptop to it.
2. Double-click **`Firewall-Setup.cmd`** and approve the admin prompt (Sunshine allowed on the local network only).
3. Pin the phone network so Windows never hops away mid-game and treats it as metered. From a command prompt in this folder, using the Wi-Fi name the laptop shows:
   ```
   Firewall-Setup.cmd -PinNetwork "HONOR X7d"
   ```
4. Double-click **`Run-Test.cmd`**. Do **not** run it as administrator. Press Enter when asked, wait through two ~90-second latency phases, then try a Moonlight stream (add the laptop IP the test prints).
5. On the phone, open **Link Check** and tap **Run link test**. It finds the laptop by itself. Tap **Copy report**.
6. Send back the `m0-report-*.txt` file and the Link Check report.

Laptop-hotspot mode instead: `Run-Test.cmd -Mode LaptopHotspot`. Other options: `-LagSeconds 180` (longer latency test), `-SkipLagTest`.

## Clean up
From a command prompt in this folder: `Firewall-Setup.cmd -Remove` (rules) and `Firewall-Setup.cmd -Remove -PinNetwork "HONOR X7d"` (un-meter). The test restores the hotspot and Wi-Fi scan settings by itself.
