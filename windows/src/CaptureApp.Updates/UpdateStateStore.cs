using System.Text.Json;
using System.Text.Json.Nodes;

namespace CaptureApp.Updates;

public interface IUpdateStateStore
{
    UpdateLedgerState Load();

    void Save(UpdateLedgerState state);
}

/// <summary>Reads and writes the <c>updates</c> section of settings.json, leaving other sections untouched.</summary>
public sealed class SettingsFileUpdateStateStore(string settingsPath, Action<string>? log = null) : IUpdateStateStore
{
    private const string Section = "updates";
    private static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public UpdateLedgerState Load()
    {
        try
        {
            if (ReadRoot()[Section] is JsonNode node)
            {
                return node.Deserialize<UpdateLedgerState>(Options) ?? new UpdateLedgerState();
            }
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException)
        {
            // Unreadable settings must not block updates; start from a clean ledger.
        }

        return new UpdateLedgerState();
    }

    /// <summary>Best effort: a failed write is logged, never thrown (updates must not break on a read-only settings file).</summary>
    public void Save(UpdateLedgerState state)
    {
        var temporary = settingsPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            JsonObject root;
            try
            {
                root = ReadRoot();
            }
            catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException)
            {
                root = [];
            }

            root[Section] = JsonSerializer.SerializeToNode(state, Options);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(settingsPath))!);
            File.WriteAllText(temporary, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, settingsPath, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            log?.Invoke($"Could not save update state: {error.Message}");
            try
            {
                File.Delete(temporary);
            }
            catch (Exception cleanup) when (cleanup is IOException or UnauthorizedAccessException)
            {
                // Nothing more to do.
            }
        }
    }

    private JsonObject ReadRoot() =>
        File.Exists(settingsPath) && JsonNode.Parse(File.ReadAllText(settingsPath)) is JsonObject root ? root : [];
}
