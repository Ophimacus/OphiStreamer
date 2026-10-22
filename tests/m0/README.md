# Milestone 0: hardware proof

Target laptop: **Acer Nitro 5 AN515-52, Windows 11** (usually an Intel Wireless-AC 9560 card).

## Before you start
1. Copy this `m0` folder to the laptop.
2. **Connect the laptop to your router's 5 GHz Wi-Fi.** Intel cards only allow a 5 GHz hotspot while the laptop is also connected to a 5 GHz Wi-Fi network; Ethernet alone is not enough.
3. Turn off Mobile Hotspot in Settings (the test turns it on itself).
4. Have the Honor X7d nearby with **Moonlight** (Play Store) installed, and Sunshine installed on the laptop.

## Setup checklist (affects the results)

**Laptop**
- Plugged into the charger, power mode **Best performance**.
- Power Options → advanced → **Wireless Adapter Settings → Power Saving Mode: Maximum Performance** (on AC).
- Device Manager → Intel Wireless-AC 9560 → Advanced: **Roaming Aggressiveness: Lowest**, **MIMO Power Save Mode: No SMPS**, **Preferred Band: 5 GHz**.
- Latest Intel Wi-Fi driver from intel.com (Acer's is old).
- Lid open (antennas are in the screen bezel).
- Pause Steam downloads, OneDrive and Windows Update: the hotspot shares one radio with the laptop's internet.

**Router**
- 5 GHz on channel **36, 40, 44, 48** or **149–161** (not radar/DFS channels), 80 MHz width. The hotspot follows the router's channel.

**Phone (Honor X7d)**
- Battery: power saving **off**; Moonlight set to **no battery restrictions** (Settings → Apps → Moonlight → Battery).
- Wi-Fi settings: turn off **Wi-Fi+** / auto-switch to mobile data if present.
- Moonlight: 1280×720 or 1920×1080 at **60 fps**, bitrate **15–20 Mbps** to start, **H.265 (HEVC)**, frame pacing **lowest latency**, **performance overlay on**.
- Run the **OphiStreamer Tester** app once on your normal home Wi-Fi first (baseline), then on the hotspot.

**Sunshine**
- Check the Sunshine log says it's using **NVENC** (the NVIDIA GPU), not the Intel iGPU.

## Run
1. Double-click **`Firewall-Setup.cmd`** and approve the admin prompt. This adds temporary rules for Sunshine on the hotspot network.
2. Double-click **`Run-Test.cmd`**. Do **not** run it as administrator; the point is to prove the app won't need admin.
3. Follow the prompts: connect the phone, wait through two ~90-second latency phases, then try a Moonlight stream.
4. Send back the `m0-report-*.txt` file it creates (it doesn't contain your hotspot password).

Options: `Run-Test.cmd -NoPhone` (no phone available), `-LagSeconds 180` (longer latency test), `-SkipLagTest`.

## Clean up
Run `Firewall-Setup.cmd -Remove` from a command prompt in this folder. The test script restores the hotspot and Wi-Fi settings by itself.
