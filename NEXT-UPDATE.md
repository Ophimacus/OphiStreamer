# Two-phone co-op and session learning

Status: implemented in Windows 0.3.0 and Android 0.6.0. The Windows build passed 24 policy checks; Android's expanded player-view, controls, co-op and learning suite passed 28 tests. These are prerelease updates; the physical two-phone acceptance test below is still pending.

## Try the update

1. Install the [Windows update](https://github.com/Ophimacus/OphiStreamer/releases/download/windows-latest/OphiStreamerSetup.exe) and the [Android update](https://github.com/Ophimacus/OphiStreamer-Android/releases/download/latest/OphiStreamer-arm64.apk) on both phones.
2. Keep the laptop and guest phone on the first phone's 5 GHz hotspot. Pair the guest manually with Apollo, then disconnect both streams for setup.
3. In Windows Settings, save/test the Apollo login, refresh paired phones, select the guest, check **Allow two phones (co-op)** and click **Apply co-op**.
4. On phone 2, open the quick menu's **App** tab and enable **This phone joins another player**. Start streaming from the host phone first; after video appears, tap **Join game** on the guest. The game must support local multiplayer.
5. For learning, open **App → Session learning → Learn from my streams**. Select Solo, Co-op host or Guest to inspect that role's reports. Learning is optional and off by default; accept a suggestion with **Apply next stream**.

Build evidence: [Windows build and checks](https://github.com/Ophimacus/OphiStreamer/actions/runs/40397524106), [Android build and tests](https://github.com/Ophimacus/OphiStreamer-Android/actions/runs/40424880015).

## Verified Apollo behaviour

Apollo v0.4.6 and upstream support multiple clients resuming the same running game. There is no `channels` setting in these Apollo config parsers; the earlier plan to set `channels=2` was incorrect.

Each stream has a separate input context; Apollo allocates virtual controllers from a global pool. Do not shift controller numbers in Android. Player order depends on connect order, existing PC controllers, and the game. A physical two-phone co-op test is still required.

References checked against upstream commit adc5c5a0bd80831ce495434bb16aee2cd4175fb8:
- https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/nvhttp.cpp
- https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/input.cpp
- https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/confighttp.cpp

## Windows co-op setup

1. Pair the second phone manually in Apollo using its PIN. Existing phone-link trust is not widened to the whole subnet.
2. In OphiStreamer Settings, refresh paired phones, select the guest by its Apollo UUID, and explicitly apply co-op mode. Disconnect the guest before changing permissions.
3. Guest permissions are list apps + view + controller (50331904), without launch/quit, keyboard, or mouse. Disable the guest's forced virtual display so both share the existing capture.
4. Back up the complete original guest record before changing it. Read back to verify. Restore on explicit disable; if settings changed externally, stop and ask the user to resolve the conflict rather than overwriting them.
5. Show actual connected-client count from Apollo's local authenticated API. Keep the laptop screen off while another stream remains; restore after the last stream ends. Unknown/stale count is not reported as zero.

Co-op mode describes supported app behaviour, not a hard server limit: Apollo may accept additional clients independently. No automatic Apollo restart or full config rewrite is needed.

## Phone experience

- Role setting: host phone or co-op guest. Guest setup joins the first phone's hotspot instead of creating another one.
- Guest Home action is Join game. It refuses when no host game is running and never falls back to launching or quitting another game if the host changes games during connection.
- Guest disconnect leaves the game running. Quit, clipboard and advanced PC-command actions are hidden in the guest menu; Apollo permissions enforce the important restrictions at the host.
- Guest does not request another virtual display. Co-op uses per-stream 720p/60, SDR, and at most 8 Mbps per phone (metered and unmetered); saved solo preferences remain intact.
- Touch controls stay automatic per phone. Controller role is not labelled P1/P2 as a guarantee.
- Start the host first, wait for video, then join the guest. Apollo has one pending handshake slot, so avoid starting both simultaneously.

## Session learning

- Opt-in, local-only reports, scoped by PC, hashed network signature, metered state and solo/shared-host/guest role.
- Bounded history: up to 24 scopes, 8 reports each. Reset clears history and disables learning.
- Uses delivered/missing video-frame counters, connected duration and observed decoder averages. Frame loss is not presented as packet loss or displayed FPS.
- Recommendations need two qualifying sessions at matching settings, each at least 2 minutes and 300 delivered frames, with recent evidence. Exclude network changes and counter discontinuities.
- Repeated network-frame loss can recommend a lower bitrate; repeated decoder delay beyond the frame budget can recommend lower FPS.
- No automatic quality increases, codec guesses or mid-session changes. A player can accept a reduction for the next matching stream, cancel it, or keep manual settings. Saved solo settings are not overwritten.

## Individual player views (Android 0.6.0)

- During a stream, open **Quick menu → Display → Player view**. Choose **Player 1** on one phone and **Player 2** on the other. Choose **Left / right** or **Top / bottom** to match the game's actual split-screen layout. These labels select picture sections; they do not assign controller slots.
- This is local picture cropping from the same captured game. It does not create a second virtual monitor, render another camera, reduce received bandwidth, or change the stream resolution. Each phone still decodes the full stream. The selected section fits without distortion, so black bars may remain and detail is limited by the original split-screen resolution.
- **Show full picture for menus** temporarily reveals the whole screen. **Return to my player view** restores the selected section without changing its saved profile. No automatic menu detection is attempted.
- Selection is saved separately on each phone for each PC and streamed app. Launching all games through the Desktop entry shares the Desktop profile; launch individual game entries for individual profiles.
- Crop affects the video surface only. Touch controls remain on the full phone screen, with Auto / Always / Off, existing themes, and live layout editing under **Controls**. Auto hides touch controls when a physical controller connects and shows them when it leaves. Hiding touch controls releases their held inputs.
- Each phone uses its own Apollo input context, with no manual P1/P2 gamepad offset. The guest still needs controller permission from Windows co-op setup, and the game assigns the actual players. USB/Bluetooth controllers and touch gamepad buttons are supported on the guest.
- Cropped-picture background taps do not send mouse clicks at incorrect coordinates. Use controller/touch gamepad input there; return to Full picture for desktop mouse use. Free zoom is available only with Full picture selected.
- Available with the standard 2D renderer on Android 7+. Older Android and AI 3D modes retain Full picture.
- Start with Sparking! ZERO's local split-screen mode. Keep Full picture for Demon Slayer 1/2 unless an actual separate-view layout is confirmed; cropping cannot create a missing camera.

Device checks: confirm both selected halves and HUDs, full-picture menu switching, rotation, reconnect/relaunch persistence, and mixed physical/touch controls. Android layout tests verify measured viewport and video bounds but cannot confirm the device's hardware surface composition.

## Acceptance test before public release

- Host starts a co-op game; guest joins the same picture; each controller controls a different player.
- Test physical controllers, touch controls, and mixed control on both devices.
- Guest cannot close or replace the game, including from alternate entry points.
- Guest disconnect leaves host streaming. Host disconnect while guest remains does not prematurely restore screen topology; last disconnect restores it.
- Reconnect both phones sequentially; verify player assignments in the game after reconnect.
- Two clean sessions do not trigger reductions. Two qualifying bad sessions produce an explainable recommendation; applying it affects only the next matching stream.
- A manual setting change, disabled learning, reset, different PC/network or different role prevents an old queued change applying.
- Verify fresh install, update, and co-op disable/restoration. Test heat and encoder load on the Acer and hotspot phone.

Deferred: an authenticated encrypted trusted-phone enrollment service for automatic guest pairing; durable player-slot assignment (game/host dependent); session-based automatic quality increases.
