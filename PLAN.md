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
