# OphiStreamer

One-click Windows tray utility for direct, low-latency game streaming (Sunshine on the PC → Moonlight on an Android phone) over the laptop's Mobile Hotspot. See [PLAN.md](PLAN.md).

| Folder | What it is |
|---|---|
| `windows` | **OphiStreamer for Windows**: tray app with one-click / automatic Gaming mode (lag fix, phone keep-alive, reconnect watchdog, connection log). Download: [OphiStreamer.exe](https://github.com/Ophimacus/OphiStreamer/releases/download/windows-latest/OphiStreamer.exe) |
| `tests/m0` | Milestone 0 hardware proof for the Windows laptop. See [tests/m0/README.md](tests/m0/README.md) |
| `android` | **OphiStreamer Tester**, an Android app for the phone that will stream: checks the hotspot band, signal, Sunshine ports and latency |

## Android tester
Each push to `main` that changes `android/` builds the APK on GitHub Actions and publishes it to the **android-latest** release:

`https://github.com/<owner>/<repo>/releases/download/android-latest/OphiStreamer-Tester.apk`

On the phone: download it, allow "Install unknown apps" for the browser, and install. Each build is signed with a fresh debug key, so uninstall the old version before installing a new one.
