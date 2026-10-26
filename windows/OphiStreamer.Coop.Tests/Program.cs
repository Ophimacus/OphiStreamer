using System.Text.Json.Nodes;
using OphiStreamer.Core;

int passed = 0;
void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
    passed++;
}
void Reject(Action action, string message)
{
    try { action(); }
    catch (InvalidOperationException) { passed++; return; }
    throw new Exception(message);
}

var original = JsonNode.Parse("""
{
  "uuid":"guest-id", "name":"Phone 2", "display_mode":"1920x1080x60", "perm":117448448,
  "enable_legacy_ordering":false, "allow_client_commands":true, "always_use_virtual_display":true,
  "do":[{"cmd":"custom launch", "elevated":true}],
  "undo":[{"cmd":"custom cleanup", "elevated":false}], "connected":false
}
""")!.AsObject();
var unchanged = original.DeepClone();
var guest = CoopGuestPolicy.GuestRecord(original);
Check(JsonNode.DeepEquals(original, unchanged), "Policy mutated original record.");
Check(guest["perm"]!.GetValue<uint>() == 50331904, "Incorrect guest permission mask.");
Check((CoopGuestPolicy.GuestPermissions & (1u << 26)) == 0, "Guest must not have launch/cancel rights.");
Check((CoopGuestPolicy.GuestPermissions & 256) != 0, "Guest controller input missing.");
Check(!guest["always_use_virtual_display"]!.GetValue<bool>(), "Guest should not force another virtual display.");
Check(!guest.ContainsKey("connected"), "Read-only presence was included in update.");
foreach (var key in new[] { "uuid", "name", "display_mode", "enable_legacy_ordering", "allow_client_commands", "do", "undo" })
    Check(JsonNode.DeepEquals(original[key], guest[key]), "Changed preserved guest field " + key);
var restored = CoopGuestPolicy.Restore(guest, original);
Check(JsonNode.DeepEquals(restored, CoopGuestPolicy.ReadRecord(original)), "Restore lost original settings.");
Check(JsonNode.DeepEquals(CoopGuestPolicy.Restore(restored, original), restored), "Restore retry should be idempotent.");
var edited = (JsonObject)guest.DeepClone();
edited["name"] = "Renamed in Apollo";
Reject(() => CoopGuestPolicy.Restore(edited, original), "External edits must prevent automatic restore.");
edited = (JsonObject)guest.DeepClone();
edited["do"] = new JsonArray();
Reject(() => CoopGuestPolicy.Restore(edited, original), "External command edits must not be overwritten.");
var emptyCommands = (JsonObject)original.DeepClone();
emptyCommands.Remove("do"); emptyCommands.Remove("undo");
var normalized = CoopGuestPolicy.ReadRecord(emptyCommands);
Check(normalized["do"] is JsonArray { Count: 0 } && normalized["undo"] is JsonArray { Count: 0 }, "Missing optional commands must normalize to empty arrays.");
var incomplete = (JsonObject)original.DeepClone(); incomplete.Remove("allow_client_commands");
Reject(() => CoopGuestPolicy.GuestRecord(incomplete), "Missing schema fields must fail closed.");
incomplete = (JsonObject)original.DeepClone(); incomplete["perm"] = -1;
Reject(() => CoopGuestPolicy.GuestRecord(incomplete), "Invalid permission value must fail closed.");
var list = JsonNode.Parse("""
{"status":true,"named_certs":[{"uuid":"one","name":"Host phone","connected":true},{"uuid":"two","name":"Guest phone","connected":false}]}
""")!.AsObject();
var clients = CoopGuestPolicy.ReadClients(list);
Check(clients.Count(c => c.Connected) == 1, "Active count must use connected, not paired count.");
Check(clients[1].Name == "Guest phone" && !clients[1].Connected, "Presence/name lost.");
list["named_certs"]![1]!["connected"] = "false";
Reject(() => CoopGuestPolicy.ReadClients(list), "Ambiguous presence must fail closed.");
Reject(() => CoopGuestPolicy.ReadClients(new JsonObject()), "Missing client list must be unknown, not zero.");
Console.WriteLine($"PASS: {passed} co-op policy checks (no host access).");
