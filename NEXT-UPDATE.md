# Two-phone co-op and session learning

Status: implemented in Windows 0.3.0 and Android 0.5.0. Both release builds passed on 2026-10-26, including 24 Windows policy checks and 20 Android tests. Downloadable prerelease updates are published; the physical two-phone acceptance test below is still pending.

## Try the update

1. Install the [Windows update](https://github.com/Ophimacus/OphiStreamer/releases/download/windows-latest/OphiStreamerSetup.exe) and the [Android update](https://github.com/Ophimacus/OphiStreamer-Android/releases/download/latest/OphiStreamer-arm64.apk) on both phones.
2. Keep the laptop and guest phone on the first phone's 5 GHz hotspot. Pair the guest manually with Apollo, then disconnect both streams for setup.
3. In Windows Settings, save/test the Apollo login, refresh paired phones, select the guest, check **Allow two phones (co-op)** and click **Apply co-op**.
4. On phone 2, open the quick menu's **App** tab and enable **This phone joins another player**. Start streaming from the host phone first; after video appears, tap **Join game** on the guest. The game must support local multiplayer.
5. For learning, open **App → Session learning → Learn from my streams**. Select Solo, Co-op host or Guest to inspect that role's reports. Learning is optional and off by default; accept a suggestion with **Apply next stream**.

Build evidence: [Windows build and checks](https://github.com/Ophimacus/OphiStreamer/actions/runs/40397524106), [Android build and tests](https://github.com/Ophimacus/OphiStreamer-Android/actions/runs/40397803449).

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
