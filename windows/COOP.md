# Windows co-op integration (0.3.0)

Opt-in is off by default. Save/test the Apollo web login in Settings, manually pair phone 2 in Apollo, then refresh paired phones and explicitly select the guest. Disconnect the guest before checking **Allow two phones (co-op)** and clicking **Apply co-op**. The regular Save button does not apply co-op. Uncheck and Apply while the guest is disconnected to restore its original record. No automatic restore on app exit.

Apply reads the current authenticated `/api/clients/list`, persists a full guest backup before writing, then posts the full preserved record to `/api/clients/update`. Only `perm=50331904` and `always_use_virtual_display=false` change. Commands (including elevated commands), command allowance, display mode, name and ordering remain intact. The Windows confirmation explicitly discloses preserved commands. Read-back must match before success. Failed/ambiguous requests retain recovery state; retry or explicitly disable. Outside edits cause a conflict instead of silently overwriting them. The guest must be disconnected for either transition. Restore the original guest before selecting another.

No `/api/config` calls, channels changes or co-op restarts. Apollo has dynamic concurrent sessions; co-op is a local preference and guest permission profile, not an enforced session quota. Existing Repair retains its explicit restart API, and connection loss reports an unconfirmed restart rather than false success.

## Public integration

- `ApolloClient.ActiveClientCount`: `int?`, count of `named_certs[].connected == true`, independent of the opt-in when phone-only screen is on. Null until a successful poll, on failure, when older than 15 seconds, or when both toggles are off. Includes all connected paired clients, not only the selected guest.
- Poll every 5 seconds when `AppSettings.CoopEnabled || AppSettings.PhoneOnlyScreen`. No phone registration, leases or unauthenticated heartbeat.
- `ApolloClient.Clients`: nullable read-only list of `ApolloClientPresence(Uuid, Name, Connected)`; `ClientsUpdatedAt` and `ClientStatusError` provide freshness/error context. Local Settings displays names/presence.
- `ListClientsAsync()`: explicit authenticated refresh for selecting a guest before opting in; returns `(Clients, Error)`.
- `ApplyCoopAsync(bool enabled, string? guestUuid)`: local desktop integration only, returns null on success or an error including rejected JSON. Disable uses the backed-up UUID rather than the current dropdown selection.
- `CoopEnabled`, `CoopCapacity` (2/1 requested app preference), `CoopGuestUuid`, `CoopApplyPending` are read-only ApolloClient properties.
- `GET http://PC:47900/status` adds `coopEnabled: bool`, `coopCapacity: int`, `activeClients: int|null`. No new write routes, names/UUIDs/commands/credentials are exposed through public status. Existing gateway/loopback trust stays unchanged.
- App wires `new ScreenSwitch(settings, () => apollo.ActiveClientCount)`. ScreenSwitch remains separately owned.

## Verified upstream contract

Verified using `gh api` before implementation against ClassicOldSong/Apollo commit `adc5c5a0bd80831ce495434bb16aee2cd4175fb8`:

- [confighttp.cpp](https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/confighttp.cpp): authenticated GET `/api/config` returns flat string config plus status/platform/version/vdisplayStatus metadata; POST replaces the file. These APIs are intentionally unused here. GET `/api/clients/list` returns `{status:true,named_certs:[...]}`. POST `/api/clients/update` is a full record replacement using uuid, name, display_mode, perm, enable_legacy_ordering, allow_client_commands, always_use_virtual_display, do, undo.
- [nvhttp.cpp](https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/nvhttp.cpp): `get_all_clients()` sets `connected` from RTSP session UUID membership; `/cancel` requires launch permission. List presence counts connected clients, not exact transport or video stream count.
- [crypto.h](https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/crypto.h): controller=256, list=16777216, view=33554432; sum=50331904. Launch=67108864 is excluded. Later-paired clients default to list/view without controller input.
- [config.cpp](https://github.com/ClassicOldSong/Apollo/blob/adc5c5a0bd80831ce495434bb16aee2cd4175fb8/src/config.cpp): no streaming `channels` parser. Writing that key cannot implement a capacity limit.

## Limits and validation

The guest must join the already-running game using its Apollo client. Connectivity depends on hotspot routing/isolation, and games must support separate controllers. Preserved custom commands may still execute according to Apollo behavior; this is not a sandbox. This version does not clear them or grant file/keyboard/mouse/clipboard/launch permissions. No session leases, credential sharing, or relaxed subnet trust is introduced.

Apollo provides no conditional update or disconnected-only transaction. A guest can connect or an administrator can edit a record between the read and write; the local gate and read-back reduce but cannot eliminate that race. Do not edit the selected client concurrently in Apollo. Apollo may invalidate another web login when the background reader authenticates.

Run the isolated policy checks without contacting Apollo:

```powershell
dotnet run --project windows/OphiStreamer.Coop.Tests
dotnet build windows/OphiStreamer/OphiStreamer.csproj
```

No application launch, installation, deployment, service restart or live host mutation is needed for these checks.
