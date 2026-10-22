# Milestone 0: hardware proof

Target laptop: **Acer Nitro 5 AN515-52, Windows 11** (usually an Intel Wireless-AC 9560 card).

## Before you start
1. Copy this `m0` folder to the laptop.
2. **Connect the laptop to your router's 5 GHz Wi-Fi.** Intel cards only allow a 5 GHz hotspot while the laptop is also connected to a 5 GHz Wi-Fi network; Ethernet alone is not enough.
3. Turn off Mobile Hotspot in Settings (the test turns it on itself).
4. Have the Steam Deck nearby with Moonlight installed, and Sunshine installed on the laptop.

## Run
1. Double-click **`Firewall-Setup.cmd`** and approve the admin prompt. This adds temporary rules for Sunshine on the hotspot network.
2. Double-click **`Run-Test.cmd`**. Do **not** run it as administrator; the point is to prove the app won't need admin.
3. Follow the prompts: connect the Deck, wait through two ~90-second latency phases, then try a Moonlight stream.
4. Send back the `m0-report-*.txt` file it creates (it doesn't contain your hotspot password).

Options: `Run-Test.cmd -NoDeck` (no Steam Deck available), `-LagSeconds 180` (longer latency test), `-SkipLagTest`.

## Clean up
Run `Firewall-Setup.cmd -Remove` from a command prompt in this folder. The test script restores the hotspot and Wi-Fi settings by itself.
