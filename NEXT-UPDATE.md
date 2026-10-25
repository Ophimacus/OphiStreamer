# Next update: two phones, one laptop (couch co-op)

Status: planned, not started. Build after the current test round (stage 4, installer, screen switch, new on-screen buttons) is reported.

## Goal

One laptop streams one game to two phones at once. Both phones show the same picture. Each phone's controller is its own player (player 1 and player 2), for split-screen and couch co-op games.

Out of scope: two different games at once, one per phone. Apollo streams a single Windows desktop, so that would need two Windows sessions or virtual machines, which is too heavy for the GTX 1050 Ti.

## Step 0: manual test first (no code)

Before building anything, confirm Apollo does what we need on the Acer:

1. In Apollo's web panel (https://localhost:47990): Configuration > Advanced > set `channels` to 2. Save and restart Apollo.
2. Phone 2 joins phone 1's 5 GHz hotspot. Pair phone 2 in Artemis or OphiStreamer.
3. In Apollo > Clients, give phone 2 the input permissions: controller, and touch/mouse if wanted. New clients only get "view streams" and "list apps" by default.
4. Start a game on phone 1, then connect phone 2 to the same game.
5. Check and write down:
   - [ ] Both phones show the picture.
   - [ ] Each GameSir moves a different player in a co-op game. If both move player 1, this whole plan needs a different approach.
   - [ ] Picture shape on phone 2. Apollo's virtual display uses phone 1's resolution, so a different phone gets black bars.
   - [ ] Smoothness on both phones, and phone 1's heat and battery, since it carries the hotspot plus its own stream.
   - [ ] Laptop encoder load at 720p and at 1080p.

The result decides what we build. Everything below assumes separate controllers work.

## What to build

### Laptop app (Windows)

- **Trusted phones list.** Today the phone link only trusts the Wi-Fi gateway, which is the phone running the hotspot. Phone 2 is not the gateway, so its pairing without a PIN, Repair and calibration are refused.
  - Add a list of trusted phones: phone 1 (the gateway) plus phones approved once from the laptop app with a "Phone 2 wants to connect: Allow?" notice.
  - Remember each phone by its pairing name and the certificate Apollo issued it, not by IP address, because the hotspot can hand out new addresses.
- **Two-phone switch in Settings:** "Let a second phone join (co-op)". When turned on, it:
  - Sets Apollo `channels` to 2 through Apollo's web API, and back to 1 when turned off.
  - Grants the second phone controller input permission in Apollo automatically after pairing, so nobody has to open Apollo's web panel.
- **Screen switch** ("show the game only on my phone"): turn the laptop screen back on only when *both* phones have disconnected, not when the first one leaves.
- **Main page:** show "Phones: 2 connected" with each phone's name and its connection quality.
- **Keep-alive / lag fix:** check that Wi-Fi tuning and keep-alive pings work with two phones. Ping both.
- **Connection log:** record which phone joined and left, and when.

### Phone app (Android)

- **Join as player 2.** On Home, when the laptop is already streaming to another phone, the Play button reads "Join game (player 2)" instead of starting a new game. It joins the running session rather than launching or quitting anything.
- **Joining without a hotspot of its own.** Phone 2 joins phone 1's hotspot. The first-run setup needs a branch: "Is this the phone with the hotspot?" If not, skip the hotspot step and show "Join the other phone's hotspot".
- **In-stream menu.** On phone 2, hide "Quit game", or make it ask first, so player 2 can't close the game on player 1. "Disconnect" leaves only phone 2.
- **Player badge.** Show a small "P1" or "P2" badge for a few seconds when the stream starts, so each person knows which player they are.
- **Touch controls.** Auto mode works per phone, so phone 2 can use touch controls while phone 1 uses its GameSir.
- **Quality.** If two phones share the hotspot, the connection check and calibration should suggest a lower bitrate for each phone, about 60%, so the hotspot isn't overloaded.

## Risks and open questions

- Whether Apollo gives each client its own controller. This is the main unknown, which is why step 0 comes first.
- The hotspot phone's heat and battery with two streams. Suggest keeping phone 1 charging.
- Different phone screen shapes mean black bars on phone 2, which is acceptable for co-op.
- 1080p/120 to two phones may be too much for the GTX 1050 Ti's encoder. Default to 720p when two phones are connected.
- Apollo's per-client permissions API needs checking on the installed Apollo version before automating it.

## Done when

- Two Honor phones (or any two phones) on phone 1's hotspot both stream the same game smoothly at 720p.
- Each GameSir controls a different player.
- Phone 2 pairs without typing a PIN after one "Allow" on the laptop.
- The laptop screen comes back only after both phones disconnect.
- Nothing changes for someone using one phone. The two-phone switch is off by default.
