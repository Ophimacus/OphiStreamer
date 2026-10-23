# OphiStreamer — Build Plan

A Windows tray utility that turns a laptop's Wi-Fi card into a low-latency, direct link for game streaming (Sunshine on the PC → Moonlight on an Android phone) with one click.

Works on any Windows 10 (2004+) / Windows 11 PC whose Wi-Fi card supports Mobile Hotspot. Not tied to any specific hardware.

**First target setup:** Acer Nitro 5 AN515-52, Windows 11 (usually an Intel Wireless-AC 9560) → **Honor X7d** (Android) running Moonlight, connected directly to the laptop's hotspot.

**Intel 5 GHz rule** (Intel support article 000029083): Intel cards only allow a 5 GHz hotspot while the PC is *also connected to a 5 GHz Wi-Fi access point*. Ethernet alone is not enough. So on Intel laptops the normal setup is: laptop on the router's 5 GHz Wi-Fi → hotspot shares that radio on 5 GHz → the lag fix (scan off) matters most here. The app must detect this case and tell the user "Connect to your 5 GHz Wi-Fi first".

---

## 1. Core design decisions

| Decision | Choice | Why |
|---|---|---|
| Runtime | **C# / .NET 10 LTS** (supported to Nov 2028) | Stable, native Windows APIs, single-file self-contained `.exe` |
| UI | **WPF** window + WinForms `NotifyIcon` for the tray (both built into .NET 10) | WPF can deliver the SteamOS-style look (gradients, rounded cards, big toggles); WinForms only supplies the tray icon. No extra packages |
| Hotspot control | **`NetworkOperatorTetheringManager`** (official WinRT API) | Start/stop, band, client list, SSID/password — no registry hacks |
| Lag fix | **`WlanSetInterface`** (wlanapi.dll): background scan **off**, media streaming mode **on** | No admin needed; Windows reverts it when the app's handle closes (even on crash); Wi-Fi can still reconnect |
| Admin rights | **Only once, in the installer** | Installer creates firewall rules + disables hotspot idle timeout. The app itself runs as a normal user |
| Installer | **Inno Setup** | Free, mature, scriptable |
| Third-party packages | **None** | Fewer breakage points |

Reference / prior art:
- catid/WLANOptimizer (BSD-3) — `WlanSetInterface` technique, re-apply every ~11 s
- jfhr/mobile-hotspot (MIT) — connection-profile selection, client connect/disconnect polling
- t4rra/hotspot-helper (archived) — confirms 5 GHz + no-scan approach for streaming

---

## 2. Version 1 scope

### Must-have
1. **One-click toggle** — hotspot ON + streaming mode ON (scan off).
2. **Automatic restore** — everything back to normal on toggle-off, phone gone, sleep, logoff, exit, crash.
3. **Firewall fix** — Sunshine allowed on the hotspot network (created by installer; "Repair" button re-runs it).
4. **Tray icon with two states** — ⚪ gray = off, 🟢 green = Gaming Mode active.
5. **Connection info** — hotspot name/password + "Add this PC in Moonlight: `192.168.137.1`" with copy buttons.

### Should-have (never blocks the toggle)
- **5 GHz band** — try 5 GHz; if unsupported/rejected fall back to Auto and show "Running on 2.4 GHz".
- **Band warning** — if the laptop's own internet is 2.4 GHz Wi-Fi, warn that 5 GHz hotspot isn't possible on single-radio cards.
- **Device names** — "HONOR X7d connected" from the hotspot client list.
- **Pre-flight check** before enabling — on charger? laptop on 5 GHz Wi-Fi? router on a non-DFS channel? big downloads running (they share the radio)? Warn, never block.
- **Wi-Fi card at Maximum Performance** while Gaming Mode is on (power-saving mode), restored on exit.
- **Channel + band in the tray tooltip.**
- **Setup checklist** in the window: phone battery optimisation off for Moonlight, Wi-Fi+ off, recommended Moonlight settings.

### Later (v1.1+)
- Wi-Fi adapter dropdown (v1 auto-picks)
- 6 GHz band
- Editing hotspot name/password
- "Max mode" fallback: `netsh wlan set autoconfig enabled=no` via an elevated helper, only if streaming mode alone doesn't remove lag on some adapters
- Glow animations / themes

---

## 2b. Look and feel: SteamOS-inspired

Same design language on the Windows app and the Android Link Check app (already built). Inspired by SteamOS, without any Valve/Steam names or logos.

| Token | Value | Use |
|---|---|---|
| Background | gradient `#1B2838` → `#0B0F14` | window / screen |
| Card | `#151C25`, border `#26313E`, radius 6 | grouped settings |
| Hero | gradient `#2A475E` → card | status header |
| Text / muted | `#DCDEDF` / `#8B98A5` | body / labels |
| Accent | `#1A9FFF` → `#0B6FD1` | primary button, toggles, focus ring, selection |
| Good / warn / bad | `#59BF40` / `#E6B450` / `#E5534B` | status pills |

**Approved Windows window layout (2026-10-22):**
- Title bar: app icon + "OphiStreamer", minimize/close.
- Left sidebar (~150 px): `OPHISTREAMER` wordmark, then Stream · Devices · Network · Firewall · Settings; selected item has a blue tint and a 3 px blue bar on the left.
- Stream page hero card (blue gradient when active, flat when off): "Gaming mode active / off", subtitle "HONOR X7d connected · 5 GHz · channel 44", large blue switch on the right, four stat tiles (Latency, Band, Signal dBm, Spikes; dimmed when off).
- "Connect your phone" card: hotspot name [Copy], password [Show], Moonlight address 192.168.137.1 [Copy].
- "Optimizations" card: Freeze Wi-Fi scanning (switch), Wi-Fi max performance (switch), Firewall rules, Controller driver (ViGEmBus), On charger, each with a status pill.
- Footer: "Fix stream connection" (secondary) + "Start/Stop gaming mode" (blue gradient primary).

Patterns: uppercase letter-spaced section headers; settings-style rows (label left, value right, thin dividers); status pills with a coloured dot; large stat tiles; one big gradient primary action; segmented controls; 52 dp+ touch targets; **full gamepad/keyboard navigation with a visible blue focus ring** on the Windows window. Font: Segoe UI Variable (Windows), system sans (Android).

---

## 2c. Phone + controller tuning (Honor X7d + GameSir)

**Phone facts** (spec sites): Snapdragon 685, Adreno 610, 6.77" 1610×720 LCD at 120 Hz, Wi-Fi 5 dual-band. Decoder reported as H.264/HEVC 1080p60 (the Link Check app reads the real limits from the phone).

- Stream **1280×720 @ 60 fps, HEVC, ~10 Mbps** first. The screen is 720p, so 1080p only adds decode load and bitrate. Try 90/120 fps later only if the Link Check app shows the decoder supports it.
- **Keep internet sharing on the hotspot.** Android only enables its low-latency Wi-Fi mode (radio power-save off, which Moonlight requests via `WIFI_MODE_FULL_LOW_LATENCY`) when the Wi-Fi network has validated internet. A hotspot with no internet quietly loses this.
- MagicOS: Moonlight → battery **No restrictions**, App launch **manage manually** (run in background on), power saving off, Wi-Fi+ off.
- Targets from Sunshine's docs: packet loss < 5 %, jitter < 1 ms.

**Controller (GameSir, USB-C)**
- Wired USB-C is the best case: no Bluetooth radio sharing airtime with the 5 GHz stream (if a Bluetooth model, keep the stream on 5 GHz; Bluetooth is 2.4 GHz only).
- Phone: turn on **OTG** (MagicOS can switch it off after idle).
- PC: **ViGEmBus** must be installed (Sunshine's installer offers it); Sunshine turns phone input into a virtual Xbox pad. The m0 test checks it.
- Moonlight: on-screen controls off, "mouse emulation via gamepad" off (avoids Start long-press conflicts), rumble on.
- Link Check app shows the detected controller, its USB ID, rumble support, and live button/stick input.

---

## 2c-bis. Connection modes (decided 2026-10-22)

**Mode A — Phone hotspot (primary).** Honor X7d runs a **5 GHz** hotspot (Settings → Mobile network → Personal hotspot → More → AP band → 5 GHz; turn the hotspot off before changing it). The Acer joins it as a normal 5 GHz client. No Intel restriction, no router, works anywhere. Daily flow: tap the phone's hotspot tile → Windows auto-joins → OphiStreamer **detects the phone's network and enables Gaming mode automatically** (zero clicks on PC; one-click manual toggle still available) → open Moonlight.

**Mode B — Laptop hotspot with 5 GHz trigger (fallback).** User confirmed: after the Acer briefly connects to a 5 GHz network (the "trigger", e.g. the phone hotspot), the Intel card allows the laptop hotspot on 5 GHz. Kept for other phones/tablets and as a fallback; the app can automate the trigger (connect to the saved 5 GHz profile → start hotspot).

---

## 2c-ter. Stability engineering (Mode A)

Goal: no drops, no spikes. Layers, in order of impact:

**1. Laptop Wi-Fi client (the laptop is now the one that scans/roams)**
- Lag fix stays core: `WlanSetInterface` background scan **off** + media streaming mode **on**, re-applied every ~10 s (Microsoft's own WlanScan docs: scanning makes it harder to send/receive and increases latency).
- **Pin the phone network:** for the phone hotspot profile set `netsh wlan set profileparameter name="<phone SSID>" connectionmode=auto autoswitch=No cost=Fixed` → auto-joins, never hops to another network mid-game, and Windows treats it as metered (no Windows Update / OneDrive eating the link). Done by the installer/first-run wizard (admin once).
- **Fast reconnect watchdog:** if the link drops, reconnect to the phone profile immediately via `WlanConnect` (don't wait for Windows), then re-apply the lag fix. Log every drop with RSSI/tx rate so calibration can show it.
- Wi-Fi power plan **Maximum Performance** while active; restore on exit.
- Intel adapter advanced settings (one-time, admin, shown as a checklist with "Apply" in the installer): Roaming Aggressiveness **Lowest**, MIMO Power Save **No SMPS**, U-APSD **Disabled**, Packet Coalescing **Disabled**, Preferred Band **5 GHz**. (Dell/Intel support list these options; values chosen for a fixed, single network.)
- Optional toggle "Pause location services while streaming": a forum user linked periodic jitter to Wi-Fi-based location scans (anecdotal, so it's an A/B option measured by calibration, not a default).

**2. Phone hotspot**
- 5 GHz AP band; turn off any "auto-turn-off hotspot when idle" option; **mobile data off** (no internet needed, no background downloads over the link).
- A SoftAP can sleep its radio when traffic is idle (DozyAP research), which adds latency on wake. During a stream traffic is continuous, so this mostly hits the first seconds; the PC app sends a tiny keep-alive (1 packet / 100 ms) to the phone while Gaming mode is on.
- Heat: hotspot + decoding on a Snapdragon 685 → keep 720p60 HEVC ~10 Mbps, brightness moderate; charging adds heat, so test both (calibration records it).

**3. Sunshine (the stream itself)**
- `fec_percentage` **20 → 30** on Wi-Fi (more packets survive loss; costs ~10 % extra bandwidth; calibration can tune 20–40).
- `nvenc_preset` **1** (fastest, default) and `nvenc_twopass` **quarter_res** (default; disabling it can cause bitrate overshoot and packet loss per Sunshine docs).
- `max_bitrate` = calibrated cap, so a wrong Moonlight setting can't overload the link.
- Applied via Sunshine's local web API once the user enters their Sunshine login (stored with DPAPI).

**4. Moonlight on the phone**
- 1280×720, 60 fps, HEVC, ~10 Mbps, frame pacing "lowest latency", performance overlay on during setup.

**5. Self-checking**
- Calibration (§2e) runs Mode A A/B tests: lag fix on/off, location on/off, charger on/off, FEC 20/30; keeps whatever measures best on this hardware.
- Live link chip in the window/tray: green/amber/red from 1 s ping + loss, with "why" text.

**Most-stable option noted for later:** USB tethering (cable, ~1 ms, zero Wi-Fi interference) — not usable while the GameSir occupies the phone's USB-C port; only relevant with a Bluetooth controller.

---

## 2c-host. Streaming host: Apollo + Artemis (decided 2026-10-23)

User tested both and chose **Apollo** (PC, `winget install ClassicOldSong.Apollo`) + **Artemis** (phone): "the best option there is for me".
- Apollo is a Sunshine fork. It creates a **virtual display (SudoVDA) at the phone's own resolution** when a stream starts and removes it when the app quits, remembers display settings per client, and the setup the user prefers **turns the laptop's physical screen off** during the stream.
- Benefits here: native 1610x720 (no scaling or black bars), up to 120 Hz to match the phone, and the laptop panel off means less heat and power on the Nitro 5.
- **Never run Apollo and Sunshine together** (same ports 47984-48010 and 47990; both are `sunshine.exe`). OphiStreamer's installer installs Apollo, sets `SunshineService` to Disabled if present, and the app warns if both services are running.
- Sunshine + Moonlight stays as a fallback; everything else in this plan (lag fix, pinning, calibration, ViGEmBus) works the same with either host.
- Artemis settings start point: **1610x720 (native) at 60 fps, HEVC, ~12 Mbps**; try **120 fps at ~18 Mbps** once 60 is smooth.

---

## 2c-app. One-stop Android app (decided 2026-10-23)

User doesn't want to open Artemis separately. **OphiStreamer for Android = a fork of Artemis** (GPL-3.0, `ClassicOldSong/moonlight-android`, branch `moonlight-noir`) at **github.com/Ophimacus/OphiStreamer-Android**. The fork must stay open source under GPL-3.0 with attribution to Moonlight/Artemis. Kept as a GitHub fork so upstream fixes can be merged.

Stages (each ends with an installable APK from GitHub Actions):
1. **Fork builds under its own identity:** new application ID and name so it installs next to Artemis; CI builds the APK (NDK + submodules) and publishes a `latest` release.
2. **Link Check inside:** the current Link Check screen (hotspot detection, PC discovery, latency, decoders, controller) becomes a tab; **calibration writes the stream settings directly** (resolution, fps, codec, bitrate), no manual typing.
3. **SteamOS restyle:** PC list, app grid, settings and in-stream overlay in the approved style (tokens §2b).
4. **One-tap Play:** home screen = status hero + one big PLAY button that pairs (once), checks the link and starts the stream; gamepad-navigable.

The standalone Link Check app (`android/` in this repo) stays until stage 2 replaces it.

---

## 2c-quater. Milestone 0 results (Acer + Honor X7d, 2026-10-23, phone-hotspot mode)

**Confirmed on real hardware (the core design holds):**
- `WlanSetInterface` lag fix works **without admin** (Intel Wireless-AC 9560, driver 24.10.0.4).
- Windows **undoes it when the app closes and when the app is killed**, so the crash-safety design is valid.
- Network pinning (auto-connect, no auto-switch, metered) applied fine.
- ViGEmBus present, Sunshine reachable on all ports, Moonlight streamed; user: "connection was great and responsiveness was great".
- Phone decoders: HEVC/H.264 hardware **720p at 120 fps**, so 720p120 is a real option.

**Problems found (setup, not design):**
- Laptop driver offered only **802.11a/g** ("Radio types supported: 802.11g 802.11a"), so the link ran **802.11g at 54 Mbps**. The 802.11n/ac mode is switched off in the adapter's advanced settings. Test now flags this.
- Phone hotspot started on **2.4 GHz channel 2**; the log shows it moved to **channel 36 (5 GHz)** mid-run with a **134 s disconnect** (likely the band change). Latency phases were measured mostly on the 2.4 GHz/54 Mbps link, so the A/B numbers (spikes 78 → 32, max 178 → 594 ms, 17 lost) are not a clean comparison.
- Apollo's **SudoMaker virtual display** driver is installed alongside Sunshine; check Sunshine captures the right display and encodes with NVENC.

**Next run:** 802.11ac enabled + phone fixed on 5 GHz before starting, 180 s phases, then compare.

---

## 2d. One-click experience (the promise)

**Install (once, on the Acer):** run `OphiStreamerSetup.exe` → **Install** → approve **one** Windows admin prompt. The installer, silently:
1. Installs OphiStreamer and starts it at logon (tray).
2. Installs **Apollo** (`winget install ClassicOldSong.Apollo`, ID confirmed in winget) and **ViGEmBus** (`winget install ViGEm.ViGEmBus`) if missing, and disables `SunshineService` if one exists (never two hosts). Checkboxes, ticked by default; Sunshine (`LizardByte.Sunshine`) offered as the fallback host.
3. Adds the firewall rules (Sunshine + calibration port, hotspot subnet only) and turns off the hotspot's 5-minute idle shutdown.

**First run (once):** a 3-step welcome wizard in the SteamOS style:
1. **Network check:** Intel card → "Connect this laptop to your 5 GHz Wi-Fi" (detects when done, auto-continues).
2. **Join the phone:** hotspot starts on 5 GHz and shows a **Wi-Fi QR code**; scan with the Honor camera to join (Android remembers it, so it auto-joins next time). Waits for the phone, then "HONOR X7d connected".
3. **Pair Artemis:** in Artemis tap the PC, enter the 4-digit PIN shown; the wizard shows where to type it (one-time Apollo pairing). Then it runs **calibration** (below) automatically.

**Every day after that:** one click on **Start gaming mode** (tray or window) → 5 GHz hotspot on + lag fix on → waits for the phone → phone auto-joins → "Ready", open Artemis and tap the PC (Apollo switches to the phone-sized virtual display and turns the laptop screen off). Stop: one click, or it restores by itself when the phone leaves / laptop sleeps.

**What can and can't be guaranteed**
- Guaranteed by the app: one installer, one admin prompt, one click to start/stop, automatic restore, a clear on-screen fix instead of a silent failure for every known problem.
- Depends on hardware (Milestone 0 confirms): 5 GHz on Intel needs the laptop connected to 5 GHz Wi-Fi; if the driver refuses 5 GHz, the app falls back to 2.4 GHz and says so.
- One-time manual steps that can't be automated: Artemis PIN pairing, and typing the calibrated settings into Artemis (neither Artemis nor Moonlight has a settings API). The phone app shows exactly what to enter.

---

## 2e. Calibration (both apps)

The Windows app runs a small **calibration service** on the hotspot only (TCP + UDP port **47900**, firewall-scoped to `192.168.137.0/24`; outside Sunshine's 47984–48010). The phone's Link Check app finds it at the hotspot gateway.

**Run from either app** ("Calibrate" button on PC and phone; same result shown on both):
1. **Link quality (30 s):** UDP echo every 20 ms with the Wi-Fi locks held, giving latency, jitter, loss and spike count. Repeated with the scan freeze off and on to prove the fix on this laptop.
2. **Throughput ramp (PC → phone, same direction as video):** PC sends UDP at 5, 10, 15, 20, 30, 40, 50 Mbps for 3 s each; phone reports loss and jitter per step. Highest clean step (< 1 % loss, jitter < 2 ms) = link capacity.
3. **Phone decoder + screen:** from Link Check (codec, max fps at 720p/1080p, refresh rate).
4. **Result profile:** resolution, fps, codec, **bitrate = 70 % of clean capacity** (capped by decoder), frame pacing, plus a grade (Excellent / Good / Fix needed + why). Saved on both sides with the date, channel and band.

**PC side also calibrates:** current band/channel (warns on DFS or 2.4 GHz), Wi-Fi power mode, charger, encoder in use (NVENC vs iGPU from Sunshine log). Optional: apply the bitrate cap to Sunshine through its local web API once the user enters their Sunshine login (stored encrypted with Windows DPAPI).

**Re-calibrate prompt:** when the band/channel changes or latency drifts from the saved profile.

---

## 3. Exact logic

### Toggle ON
1. Check capability (`GetTetheringCapability`). Not supported → show message, stop.
2. Pick connection profile to share: internet profile → else any connected profile → else error.
3. Set band: 5 GHz if `IsBandSupported`, else Auto.
4. Start hotspot. Failure → show error, stop (nothing else changed yet).
5. Open WLAN handle; on the connected Wi-Fi interface set `background_scan_enabled = 0`, `media_streaming_mode = 1`.
   - Interface not connected (e.g. laptop on Ethernet) → skip; nothing to optimize, not an error.
6. Start 11-second timer: re-apply step 5 (Wi-Fi reconnects reset it) and poll hotspot clients.
7. Icon → green.

### Toggle OFF / Restore (every step runs even if a previous one fails)
1. Stop timer.
2. Set `background_scan_enabled = 1`, `media_streaming_mode = 0`, then `WlanCloseHandle`.
3. Stop hotspot.
4. Icon → gray.

### Automatic restore triggers
- Phone (last client) disconnected for **2 minutes** (grace period so a screen-off or short Wi-Fi drop doesn't end the session).
- PC suspend (`SystemEvents.PowerModeChanged`), logoff/shutdown (`SessionEnding`).
- App exit.
- Hotspot stopped by Windows or user outside the app → detect on poll, run restore.
- **Crash:** Windows releases the WLAN handle → scan settings revert automatically. Hotspot may stay on; on next start the app detects "hotspot on but not ours" and offers to turn it off.

### Failure handling
| Failure | Behavior |
|---|---|
| No Wi-Fi / hotspot unsupported | Toggle disabled, "This PC can't create a hotspot" |
| No connection to share | Clear message, no partial state |
| 5 GHz rejected | Fall back to Auto, tooltip shows actual band |
| `WlanSetInterface` fails | Hotspot still works; tooltip "Lag fix unavailable on this adapter" |
| Windows idle timeout turns hotspot off | Prevented by installer; also caught by poll → restore |
| Moonlight can't find PC | UI shows `192.168.137.1` to add manually |

---

## 4. Firewall (done by installer, as admin, once)

- **Primary:** program rule allowing `sunshine.exe` (detected install path), inbound TCP+UDP, remote address `192.168.137.0/24`, all profiles (hotspot network is classified Public).
- **Fallback:** port rule TCP+UDP `47984–48010`, same subnet scope (sources disagree on exact Sunshine ports; verify against official LizardByte docs and narrow later).
- All rules named `OphiStreamer-*`; uninstaller removes them.
- "Repair stream connection" button in the app re-launches the installer's repair action (one UAC prompt, only when the user clicks it).

---

## 5. Project layout

```
OphiStreamer/
  Program.cs              startup, single-instance, leftover-hotspot check
  TrayApp.cs              tray icon, menu, power/session events
  Core/
    HotspotService.cs     capability, profile pick, band, start/stop, clients, SSID/password
    WlanStreamingMode.cs  P/Invoke wlanapi: open handle, set/reset scan + streaming mode
    SessionController.cs  ON/OFF sequences, 11 s timer, 2-min disconnect grace
    UpstreamInfo.cs       detect laptop's own Wi-Fi band for the 2.4 GHz warning
  UI/
    MainWindow.cs         small dark window: toggle, name/password, host IP, status
  installer/
    setup.iss             Inno Setup: firewall rules, idle timeout off, autostart, uninstall cleanup
```

---

## 6. Build order (each step tested before the next)

0. **Hardware proof (on the Acer + the Honor X7d).** PowerShell/C# console test:
   - hotspot starts on 5 GHz without admin
   - `WlanSetInterface` works without admin
   - **settings really revert when the process is killed** (key assumption — not stated in Microsoft docs)
   - Moonlight streams over the hotspot with the firewall rule
   - ping spikes gone vs. without the fix
1. Core services + SessionController (console harness).
2. Restore triggers (disconnect grace, sleep, logoff, exit, leftover detection).
3. Tray icon + menu.
4. Small window.
5. Installer (firewall, timeout, autostart, uninstall).

## 7. Definition of done

On the Acer + Honor X7d:
- Toggle on → stream → toggle off → normal Wi-Fi works. **10× in a row.**
- Phone off the hotspot > 2 min → laptop restores itself.
- App killed in Task Manager mid-session → scan settings reverted by Windows; next launch cleans up hotspot.
- Fresh install on a second PC: no UAC prompt after install, stream works first try.
