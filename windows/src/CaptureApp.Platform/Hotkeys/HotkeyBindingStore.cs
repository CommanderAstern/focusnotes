using System.Text.Json;
using System.Text.Json.Nodes;

namespace CaptureApp.Platform.Hotkeys;

/// <summary>Reads and updates the settings.json "shortcuts" object while preserving other settings.</summary>
public sealed class HotkeyBindingStore
{
    private readonly string _settingsPath;

    public HotkeyBindingStore(string settingsPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(settingsPath);
        _settingsPath = Path.GetFullPath(settingsPath);
    }

    public IReadOnlyDictionary<HotkeyAction, KeyChord> Load()
    {
        var bindings = new Dictionary<HotkeyAction, KeyChord>(HotkeyDefaults.All);
        var root = ReadRoot();
        if (root is null || !root.TryGetPropertyValue("shortcuts", out var shortcutsNode))
        {
            return bindings;
        }

        if (shortcutsNode is not JsonObject shortcuts)
        {
            throw new InvalidDataException("The settings shortcuts value must be a JSON object.");
        }

        foreach (var pair in shortcuts)
        {
            if (!Enum.TryParse<HotkeyAction>(pair.Key, ignoreCase: true, out var action))
            {
                continue;
            }

            if (pair.Value is not JsonValue value || !value.TryGetValue<string>(out var displayString))
            {
                throw new InvalidDataException($"The shortcut for {action} must be a string.");
            }

            KeyChord chord;
            try
            {
                chord = KeyChord.Parse(displayString);
            }
            catch (FormatException exception)
            {
                throw new InvalidDataException($"The shortcut for {action} is invalid.", exception);
            }

            var validation = HotkeyValidator.Validate(chord);
            if (!validation.IsValid)
            {
                throw new InvalidDataException($"The shortcut for {action} is not allowed: {validation.Error}");
            }

            bindings[action] = chord;
        }

        return bindings;
    }

    public void Save(IReadOnlyDictionary<HotkeyAction, KeyChord> bindings)
    {
        ArgumentNullException.ThrowIfNull(bindings);
        foreach (var (action, chord) in bindings)
        {
            if (!Enum.IsDefined(action))
            {
                throw new ArgumentOutOfRangeException(nameof(bindings), $"Unknown hotkey action '{action}'.");
            }

            HotkeyValidator.ThrowIfInvalid(chord);
        }

        var root = ReadRoot() ?? new JsonObject();
        if (root.TryGetPropertyValue("shortcuts", out var shortcutsNode) && shortcutsNode is not JsonObject)
        {
            throw new InvalidDataException("The settings shortcuts value must be a JSON object.");
        }

        var shortcuts = shortcutsNode as JsonObject;
        if (shortcuts is null)
        {
            shortcuts = new JsonObject();
            root["shortcuts"] = shortcuts;
        }

        foreach (var (action, chord) in bindings)
        {
            shortcuts[action.ToString()] = chord.DisplayString;
        }

        var directory = Path.GetDirectoryName(_settingsPath) ?? throw new InvalidOperationException("Settings path has no parent directory.");
        Directory.CreateDirectory(directory);
        var temporaryPath = $"{_settingsPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllText(temporaryPath, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporaryPath, _settingsPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    /// <summary>Validates and test-registers a new binding before atomically persisting it.</summary>
    public HotkeyRegistrationResult SaveIfAvailable(HotkeyAction action, KeyChord chord, HotkeyRegistrar registrar)
    {
        ArgumentNullException.ThrowIfNull(registrar);
        var availability = registrar.TestRegisterTemporarily(chord);
        if (!availability.Succeeded)
        {
            return availability with { Action = action };
        }

        var bindings = Load().ToDictionary(pair => pair.Key, pair => pair.Value);
        bindings[action] = chord;
        Save(bindings);
        return availability with { Action = action };
    }

    private JsonObject? ReadRoot()
    {
        if (!File.Exists(_settingsPath))
        {
            return null;
        }

        try
        {
            var node = JsonNode.Parse(File.ReadAllText(_settingsPath));
            return node as JsonObject ?? throw new InvalidDataException("The settings file root must be a JSON object.");
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("The settings file is corrupt; shortcut bindings were left unchanged.", exception);
        }
    }
}
