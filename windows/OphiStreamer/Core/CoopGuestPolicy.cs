using System;
using System.Text.Json.Nodes;

namespace OphiStreamer.Core;

/// <summary>Verified Apollo updateClient is a full-record replacement, not a permission patch.</summary>
public static class CoopGuestPolicy
{
    public const uint GuestPermissions = 50331904; // list | view | input_controller; excludes launch (/cancel).

    public static JsonObject ReadRecord(JsonObject client)
    {
        var record = (JsonObject)client.DeepClone();
        record.Remove("connected");
        foreach (var field in new[] { "uuid", "name", "display_mode" })
            if (record[field] is not JsonValue value || !value.TryGetValue<string>(out _))
                throw new InvalidOperationException("Apollo client is missing string " + field);
        if (string.IsNullOrEmpty(record["uuid"]!.GetValue<string>()))
            throw new InvalidOperationException("Apollo client UUID is empty.");
        if (record["perm"] is not JsonValue permission || !permission.TryGetValue<uint>(out _))
            throw new InvalidOperationException("Apollo client is missing uint32 perm.");
        foreach (var field in new[] { "enable_legacy_ordering", "allow_client_commands", "always_use_virtual_display" })
            if (record[field] is not JsonValue value || !value.TryGetValue<bool>(out _))
                throw new InvalidOperationException("Apollo client is missing boolean " + field);
        foreach (var field in new[] { "do", "undo" })
        {
            if (!record.ContainsKey(field)) record[field] = new JsonArray();
            if (record[field] is not JsonArray commands)
                throw new InvalidOperationException("Apollo client has invalid " + field + " commands.");
            foreach (var command in commands)
                if (command is not JsonObject entry || entry["cmd"] is not JsonValue cmd || !cmd.TryGetValue<string>(out _) ||
                    entry["elevated"] is not JsonValue elevated || !elevated.TryGetValue<bool>(out _))
                    throw new InvalidOperationException("Apollo client has an unsupported command schema.");
        }
        return record;
    }

    public static JsonObject GuestRecord(JsonObject original)
    {
        var guest = ReadRecord(original);
        guest["perm"] = GuestPermissions;
        guest["always_use_virtual_display"] = false;
        return guest;
    }

    public static JsonObject Restore(JsonObject current, JsonObject original)
    {
        current = ReadRecord(current);
        original = ReadRecord(original);
        if (!JsonNode.DeepEquals(current, GuestRecord(original)) && !JsonNode.DeepEquals(current, original))
            throw new InvalidOperationException("Guest settings changed outside OphiStreamer. Restore manually in Apollo; no client settings were overwritten.");
        return original;
    }

    public static ApolloClientPresence[] ReadClients(JsonObject response)
    {
        if (response["named_certs"] is not JsonArray clients)
            throw new InvalidOperationException("Apollo clients response is missing named_certs.");
        var result = new ApolloClientPresence[clients.Count];
        for (int i = 0; i < clients.Count; i++)
        {
            if (clients[i] is not JsonObject client ||
                client["uuid"] is not JsonValue uuid || !uuid.TryGetValue<string>(out var id) || string.IsNullOrEmpty(id) ||
                client["name"] is not JsonValue name || !name.TryGetValue<string>(out var label) ||
                client["connected"] is not JsonValue connected || !connected.TryGetValue<bool>(out var active))
                throw new InvalidOperationException("Unexpected Apollo client schema; active count is unknown.");
            result[i] = new(id, label, active);
        }
        return result;
    }
}

public sealed record ApolloClientPresence(string Uuid, string Name, bool Connected)
{
    public string Label => $"{Name} ({(Connected ? "streaming" : "disconnected")}) — {Uuid}";
}
