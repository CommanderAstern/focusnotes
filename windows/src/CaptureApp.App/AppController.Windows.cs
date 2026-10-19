using System.IO;
using CaptureApp.AppCore;
using CaptureApp.AppCore.Shell;
using CaptureApp.Core;
using CaptureApp.Platform.Hotkeys;

namespace CaptureApp.App;

internal sealed partial class AppController
{
    private SetupWindow? setupWindow;
    private SettingsWindow? settingsWindow;

    /// Raised by capture flows so the Setup tests can observe a real capture: (trigger, method or detail, OCR text found).
    internal event Action<CaptureTrigger, string, bool>? CaptureObserved;

    internal void OpenSetup(bool manual)
    {
        if (quitting) { return; }
        // A launch-time reopen happens once per launch; a manual open always works.
        if (!manual)
        {
            if (openedSetupThisLaunch) { return; }
            openedSetupThisLaunch = true;
        }

        if (setupWindow is { } open)
        {
            open.Activate();
            return;
        }

        Setup.Reload();
        var window = new SetupWindow(this, manual);
        setupWindow = window;
        window.Closed += (_, _) => { setupWindow = null; Setup.AcknowledgeVersion(); RefreshMenu(); };
        window.Show();
        window.Activate();
    }

    internal void OpenSettings(int tab = 0)
    {
        if (quitting) { return; }
        if (settingsWindow is { } open)
        {
            open.SelectTab(tab);
            open.Activate();
            return;
        }

        var window = new SettingsWindow(this, tab);
        settingsWindow = window;
        window.Closed += (_, _) => settingsWindow = null;
        window.Show();
        window.Activate();
    }

    /// Setup or Settings changed something the tray shows.
    internal void OnSetupChanged() => RefreshMenu();

    /// Step 0 was answered: hotkeys come alive and the update schedule follows the choice.
    internal void OnConsentAnswered()
    {
        RegisterHotkeys();
        RefreshMenu();
        if (updates is { IsEnabled: true } && Settings.UpdatesChoice != UpdatesChoice.Manual && !updateSchedulerStarted)
        {
            updateSchedulerStarted = true;
            _ = Task.Run(async () =>
            {
                try { await updates.RunAutomaticChecksAsync(lifetime.Token).ConfigureAwait(false); }
                catch (OperationCanceledException) { }
            });
        }
    }

    private bool updateSchedulerStarted;

    internal bool IsRegistered(HotkeyAction action) => hotkeys is not null && Setup.ConsentAnswered && !failures.ContainsKey(action)
                                                       && !Settings.DisabledShortcuts.Contains(action.ToString());

    internal void PauseHotkeys() => hotkeys?.UnregisterAll();

    /// null when the combination can be used; otherwise the reason.
    internal string? ValidateBinding(HotkeyAction action, KeyChord chord)
    {
        var validation = HotkeyValidator.Validate(chord);
        if (!validation.IsValid) { return validation.Error; }
        if (!AltGrGuard.IsSafe(chord))
        {
            var suggestion = AltGrGuard.FindNextFreeLetter(Bindings.Values);
            return "This combination types a letter on an installed keyboard layout (AltGr)." +
                   (suggestion is { } letter ? $" Try {letter.DisplayString}." : "");
        }

        foreach (var (other, existing) in Bindings)
        {
            if (other != action && existing == chord && !Settings.DisabledShortcuts.Contains(other.ToString()))
            {
                return $"{existing.DisplayString} is already used by another shortcut.";
            }
        }

        return null;
    }

    /// Test-registers the combination before saving it (§4 guard 3).
    internal HotkeyRegistrationResult TrySaveBinding(HotkeyAction action, KeyChord chord)
    {
        hotkeys ??= new HotkeyRegistrar();
        if (ValidateBinding(action, chord) is { } error) { return new(action, chord, false, 87, error); }
        try
        {
            var result = BindingStore.SaveIfAvailable(action, chord, hotkeys);
            if (result.Succeeded)
            {
                var set = Settings.DisabledShortcuts.ToHashSet(StringComparer.Ordinal);
                if (set.Remove(action.ToString())) { Settings.DisabledShortcuts = set; }
                LoadBindings();
            }

            return result;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidDataException)
        {
            return new(action, chord, false, 0, exception.Message);
        }
    }

    internal void ApplyStartAtLogin(bool enabled)
    {
        LoginItem.SetEnabled(enabled);
        Settings.StartAtLogin = enabled;
    }

    internal void ApplyUpdatesChoice(UpdatesChoice choice)
    {
        Settings.UpdatesChoice = choice;
        RefreshMenu();
    }

    internal void ApplyClipboardFallback(bool enabled) => Settings.ClipboardFallback = enabled;

    internal string CurrentNotesFolder => Settings.NotesFolder ?? Path.Combine(Platform.Shell.KnownFolders.Documents, AppInfo.Name);

    internal IReadOnlyList<CapabilityStatus> CapabilityTable() => Capabilities.Evaluate(new CapabilityInputs(
        Setup.ConsentAnswered,
        7 - failures.Count - Settings.DisabledShortcuts.Count,
        failures.Count,
        Settings.DisabledShortcuts.Count,
        Settings.ClipboardFallback,
        FolderWritable,
        Ocr.IsValueCreated ? Ocr.Value.IsAvailable : null,
        Settings.StartAtLogin,
        LoginItem.IsEnabled,
        updates?.IsEnabled == true,
        Settings.UpdatesChoice));
}
