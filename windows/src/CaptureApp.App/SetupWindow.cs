using CaptureApp.AppCore;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using CaptureApp.AppCore.Shell;
using CaptureApp.Core;
using CaptureApp.ModelInstall;
using CaptureApp.Platform.Hotkeys;

namespace CaptureApp.App;

/// The first-launch Setup flow (§5): one page per step, with progress saved after every step.
/// All decisions live in <see cref="SetupState"/>; this window only presents them.
internal sealed class SetupWindow : Window
{
    private readonly AppController controller;
    private readonly IReadOnlyList<SetupStepInfo> steps;
    private readonly StackPanel list = new() { Margin = new Thickness(12) };
    private readonly ContentControl page = new() { Margin = new Thickness(24, 20, 24, 8) };
    private readonly TextBlock status = UiKit.Text("", 12, false, "Secondary", 0);
    private int current;
    private Action? detach;

    public SetupWindow(AppController controller, bool manual)
    {
        this.controller = controller;
        steps = controller.Setup.StepsToShow(manual);
        Title = $"{AppInfo.Name} Setup";
        Width = 820;
        Height = 640;
        MinWidth = 700;
        MinHeight = 520;
        ShowInTaskbar = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        UiKit.Themed(this);

        var layout = new Grid();
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(230) });
        layout.ColumnDefinitions.Add(new ColumnDefinition());
        layout.RowDefinitions.Add(new RowDefinition());
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var sidebar = new Border { Child = new ScrollViewer { Content = list } };
        sidebar.SetResourceReference(Border.BackgroundProperty, "QuickClusterFill");
        Grid.SetRowSpan(sidebar, 2);
        layout.Children.Add(sidebar);
        var scroll = new ScrollViewer { Content = page, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(scroll, 1);
        layout.Children.Add(scroll);
        var footer = UiKit.Row(UiKit.Button("Back", () => Go(current - 1)), UiKit.Button("Next", () => Go(current + 1)),
            UiKit.Button("Close", Close));
        footer.Margin = new Thickness(24, 4, 24, 14);
        var footerGrid = new StackPanel();
        footerGrid.Children.Add(status);
        footerGrid.Children.Add(footer);
        Grid.SetColumn(footerGrid, 1);
        Grid.SetRow(footerGrid, 1);
        footerGrid.Margin = new Thickness(24, 0, 24, 0);
        layout.Children.Add(footerGrid);
        Content = layout;

        // Reopen at the first incomplete Required step; a fresh run starts at the top.
        var first = controller.Setup.FirstStepNeedingAttention;
        var start = first is { } id ? steps.ToList().FindIndex(step => step.Id == id) : 0;
        Go(Math.Max(0, start));
        Closed += (_, _) => detach?.Invoke();
    }

    private SetupState State => controller.Setup;

    private void Go(int index)
    {
        if (index < 0 || index >= steps.Count) { return; }
        detach?.Invoke();
        detach = null;
        current = index;
        RenderList();
        var info = steps[index];
        var body = new StackPanel();
        var tag = info.Class == SetupStepClass.Required ? "Required" : "Recommended";
        body.Children.Add(UiKit.Secondary($"Step {info.Number} of 8 · {tag}"));
        body.Children.Add(UiKit.Text(info.Title, 22, true, "TextPrimary", 12));
        var state = State.State(info.Id);
        if (state.Status == SetupStatus.Failed && state.Detail is { Length: > 0 } cause)
        {
            body.Children.Add(UiKit.Text(cause, 12, false, "Warning"));
        }

        switch (info.Id)
        {
            case SetupStepId.Disclosure: Disclosure(body); break;
            case SetupStepId.NotesFolder: NotesFolder(body); break;
            case SetupStepId.Shortcuts: Shortcuts(body); break;
            case SetupStepId.SelectionTest: CaptureTest(body, info.Id, CaptureTrigger.Selection); break;
            case SetupStepId.AreaTest: CaptureTest(body, info.Id, CaptureTrigger.Region); break;
            case SetupStepId.TrayIcon: TrayIcon(body); break;
            case SetupStepId.StartAtLogin: StartAtLogin(body); break;
            case SetupStepId.Updates: Updates(body); break;
            default: Semantic(body); break;
        }

        page.Content = body;
        status.Text = StatusText(info.Id);
    }

    private string StatusText(SetupStepId id)
    {
        var state = State.State(id);
        return state.Status switch
        {
            SetupStatus.Passed => "Done",
            SetupStatus.Failed => "Needs attention",
            SetupStatus.Skipped => "Not tested",
            _ => SetupSteps.Info(id).Class == SetupStepClass.Required ? "Not done yet" : "Not tested"
        };
    }

    private void RenderList()
    {
        list.Children.Clear();
        list.Children.Add(UiKit.Text("Setup", 16, true, "TextPrimary", 10));
        for (var i = 0; i < steps.Count; i++)
        {
            var index = i;
            var info = steps[i];
            var glyph = State.Status(info.Id) switch
            {
                SetupStatus.Passed => "✓",
                SetupStatus.Failed => "✕",
                SetupStatus.Skipped => "–",
                _ => "○"
            };
            var item = new Button
            {
                Content = $"{glyph}  {info.Title}",
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(8, 6, 8, 6),
                Margin = new Thickness(0, 1, 0, 1),
                FontWeight = i == current ? FontWeights.SemiBold : FontWeights.Normal,
                BorderThickness = new Thickness(0),
                Background = System.Windows.Media.Brushes.Transparent
            };
            item.SetResourceReference(Control.ForegroundProperty, State.Status(info.Id) == SetupStatus.Failed ? "Warning" : "TextPrimary");
            item.Click += (_, _) => Go(index);
            list.Children.Add(item);
        }
    }

    private void Mark(SetupStepId id, SetupStatus value, string? detail = null)
    {
        State.Mark(id, value, detail);
        controller.OnSetupChanged();
    }

    private void Finish(SetupStepId id, SetupStatus value, string? detail = null)
    {
        Mark(id, value, detail);
        if (current + 1 < steps.Count && value != SetupStatus.Failed) { Go(current + 1); } else { Go(current); }
    }

    private Button SkipButton(SetupStepId id) => UiKit.Button("Skip", () => Finish(id, SetupStatus.Skipped));

    // Step 0.
    private void Disclosure(StackPanel body)
    {
        body.Children.Add(UiKit.Text($"{AppInfo.Name} uses the following. Nothing runs, and no shortcut is registered, until you answer both choices below.", 13, false, "TextPrimary", 8));
        foreach (var bullet in new[]
                 {
                     "Global keyboard shortcuts, registered system-wide.",
                     "Reading the selected text of the app in front, only when you press Capture Selection, through UI Automation.",
                     "The clipboard fallback: it briefly sends Ctrl+C to that app, then restores your clipboard. The app's own copy may appear in Windows clipboard history.",
                     "Screen pixels, only while you drag a Capture Area.",
                     $"Writing Markdown into your notes folder, and app state into %LocalAppData%\\{AppInfo.BundleId}.",
                     "Network: only update checks and downloads from github.com and, if you later enable semantic search, model downloads from huggingface.co.",
                     "Start at login, a pre-checked option in step 6."
                 })
        {
            body.Children.Add(UiKit.Text("•  " + bullet, 13, false, "TextPrimary", 3));
        }

        body.Children.Add(UiKit.Rule());
        body.Children.Add(UiKit.Text("Clipboard fallback", 13, true));
        var use = UiKit.Radio("Use clipboard fallback", "fallback", controller.Settings.ClipboardFallback == true);
        var dont = UiKit.Radio("Don't", "fallback", controller.Settings.ClipboardFallback == false);
        body.Children.Add(use);
        body.Children.Add(dont);
        body.Children.Add(UiKit.Text("Updates", 13, true));
        var auto = UiKit.Radio("Check for updates automatically (daily)", "updates", controller.Settings.UpdatesChoice == UpdatesChoice.Auto);
        var manual = UiKit.Radio("Only when I ask", "updates", controller.Settings.UpdatesChoice == UpdatesChoice.Manual);
        body.Children.Add(auto);
        body.Children.Add(manual);
        var message = UiKit.Text("", 12, false, "Warning");
        body.Children.Add(message);
        body.Children.Add(UiKit.Row(UiKit.Button("Continue", () =>
        {
            if ((use.IsChecked != true && dont.IsChecked != true) || (auto.IsChecked != true && manual.IsChecked != true))
            {
                message.Text = "Choose one option in each group to continue.";
                return;
            }

            controller.ApplyClipboardFallback(use.IsChecked == true);
            controller.ApplyUpdatesChoice(auto.IsChecked == true ? UpdatesChoice.Auto : UpdatesChoice.Manual);
            Mark(SetupStepId.Disclosure, SetupStatus.Passed);
            controller.OnConsentAnswered();
            Go(current + 1);
        }, true)));
    }

    // Step 1.
    private void NotesFolder(StackPanel body)
    {
        body.Children.Add(UiKit.Text("Captures are saved as Markdown in this folder. The default is inside Documents.", 13, false, "TextPrimary", 8));
        var path = new TextBox { Text = controller.CurrentNotesFolder, Margin = new Thickness(0, 4, 8, 4), MinWidth = 380 };
        var result = UiKit.Text("", 12, false, "Secondary");
        void Check()
        {
            var folder = path.Text.Trim();
            var probe = AppController.ProbeNotesFolder(folder);
            var notes = new List<string>();
            if (IsOneDrive(folder)) { notes.Add("This folder is backed up by OneDrive. If files are online-only, indexing may be slow until they are downloaded; consider \"Always keep on this device\"."); }
            if (!probe.Ok)
            {
                var detail = $"Can't write to this folder: {probe.Cause}";
                if (IsProtectedFolder(folder)) { detail += " Controlled folder access in Windows Security may be blocking this app. Allow it under Windows Security → Virus & threat protection → Ransomware protection → Allow an app. Until then captures are kept safely in the app's recovery folder."; }
                Mark(SetupStepId.NotesFolder, SetupStatus.Failed, detail);
                result.SetResourceReference(TextBlock.ForegroundProperty, "Warning");
                result.Text = string.Join("\n", notes.Prepend(detail));
                Go(current);
                return;
            }

            var changed = !string.Equals(Path.GetFullPath(folder), Path.GetFullPath(controller.CurrentNotesFolder), StringComparison.OrdinalIgnoreCase);
            controller.Settings.NotesFolder = folder;
            Mark(SetupStepId.NotesFolder, SetupStatus.Passed, changed ? "Applied on restart" : null);
            result.SetResourceReference(TextBlock.ForegroundProperty, "Secondary");
            result.Text = string.Join("\n", notes.Prepend(changed ? "The folder is writable. It takes effect after you restart the app." : "The folder is writable."));
            RenderList();
            status.Text = StatusText(SetupStepId.NotesFolder);
        }

        body.Children.Add(path);
        body.Children.Add(UiKit.Row(
            UiKit.Button("Choose another folder…", () =>
            {
                var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = Directory.Exists(path.Text) ? path.Text : null };
                if (dialog.ShowDialog(this) == true) { path.Text = dialog.FolderName; Check(); }
            }),
            UiKit.Button("Check again", Check, true)));
        body.Children.Add(result);
    }

    private static bool IsOneDrive(string folder) => folder.Contains("OneDrive", StringComparison.OrdinalIgnoreCase);

    private static bool IsProtectedFolder(string folder)
    {
        var documents = Platform.Shell.KnownFolders.Documents;
        return folder.StartsWith(documents, StringComparison.OrdinalIgnoreCase);
    }

    // Step 2.
    private void Shortcuts(StackPanel body)
    {
        body.Children.Add(UiKit.Text("All seven shortcuts must be registered, changed, or turned off by you.", 13, false, "TextPrimary", 8));
        ShortcutsPanel? panel = null;
        panel = new ShortcutsPanel(controller, () => { Evaluate(); });
        body.Children.Add(panel);
        void Evaluate()
        {
            if (!State.ConsentAnswered) { return; }
            if (panel!.AllResolved) { Mark(SetupStepId.Shortcuts, SetupStatus.Passed); }
            else { Mark(SetupStepId.Shortcuts, SetupStatus.Failed, $"{controller.ShortcutFailures.Count} shortcut(s) couldn't be registered. Change or turn them off."); }
            RenderList();
            status.Text = StatusText(SetupStepId.Shortcuts);
        }

        if (State.ConsentAnswered) { Evaluate(); }
        else { body.Children.Add(UiKit.Text("Answer step 0 first; shortcuts are registered after that.", 12, false, "Warning")); }
    }

    // Steps 3 and 4: the test only verifies; a capability never depends on it.
    private void CaptureTest(StackPanel body, SetupStepId id, CaptureTrigger trigger)
    {
        var action = trigger == CaptureTrigger.Selection ? HotkeyAction.CaptureSelection : HotkeyAction.CaptureArea;
        var binding = controller.BindingText(action);
        var result = UiKit.Text("Waiting for a capture…", 13, true);
        if (trigger == CaptureTrigger.Selection)
        {
            body.Children.Add(UiKit.Text($"Select the sample text below in another app (copy it into Notepad first), then press {binding}. {AppInfo.Name} can't capture from its own windows.", 13, false, "TextPrimary", 8));
            var sample = new TextBox { Text = "The quick brown fox jumps over the lazy dog.", IsReadOnly = true, Margin = new Thickness(0, 4, 0, 8) };
            body.Children.Add(sample);
            body.Children.Add(UiKit.Secondary("Apps running as administrator can't be read; use Capture Area for those. The clipboard fallback is " +
                (controller.Settings.ClipboardFallback == true ? "on." : "off, so apps that don't share their selection will report no text.")));
        }
        else
        {
            body.Children.Add(UiKit.Text($"Press {binding}, then drag a rectangle over some text on screen. The image is saved and OCR reads it.", 13, false, "TextPrimary", 8));
        }

        body.Children.Add(result);
        void Observed(CaptureTrigger seen, string detail, bool text)
        {
            if (seen != trigger) { return; }
            dispatcherInvoke(() =>
            {
                if (trigger == CaptureTrigger.Region && !text)
                {
                    result.Text = "The area was captured, but OCR found no text. Try a region with clear text, or check the OCR models.";
                    return;
                }

                result.Text = $"Captured ({detail}).";
                Mark(id, SetupStatus.Passed, detail);
                RenderList();
                status.Text = StatusText(id);
            });
        }

        controller.CaptureObserved += Observed;
        detach = () => controller.CaptureObserved -= Observed;
        if (State.Status(id) == SetupStatus.Passed) { result.Text = "Passed earlier. Run it again any time."; }
        if (!State.ConsentAnswered) { body.Children.Add(UiKit.Text("Answer step 0 first.", 12, false, "Warning")); }
        body.Children.Add(UiKit.Row(UiKit.Button("Check again", () => Go(current)), SkipButton(id)));
    }

    private void dispatcherInvoke(Action action) => Dispatcher.BeginInvoke(action);

    // Step 5.
    private void TrayIcon(StackPanel body)
    {
        body.Children.Add(UiKit.Text("The tray icon is how you reach the menu, Setup and Settings.", 13, false, "TextPrimary", 8));
        body.Children.Add(UiKit.Text("Windows 11 may hide new icons in the overflow. Open Settings → Personalization → Taskbar → Other system tray icons and turn on " + AppInfo.Name + ", or drag the icon from the ^ overflow onto the taskbar.", 13, false, "TextPrimary", 8));
        body.Children.Add(UiKit.Row(UiKit.Button("I can see the icon", () => Finish(SetupStepId.TrayIcon, SetupStatus.Passed), true), SkipButton(SetupStepId.TrayIcon)));
    }

    // Step 6.
    private void StartAtLogin(StackPanel body)
    {
        body.Children.Add(UiKit.Text($"Start {AppInfo.Name} when you sign in, so the shortcuts are always ready. You can also manage this in Windows Settings → Apps → Startup.", 13, false, "TextPrimary", 8));
        var toggle = UiKit.Check("Start at login", controller.Settings.StartAtLogin ?? true);
        body.Children.Add(toggle);
        var message = UiKit.Text("", 12, false, "Warning");
        body.Children.Add(message);
        body.Children.Add(UiKit.Row(UiKit.Button("Apply", () =>
        {
            try
            {
                controller.ApplyStartAtLogin(toggle.IsChecked == true);
                Finish(SetupStepId.StartAtLogin, SetupStatus.Passed, toggle.IsChecked == true ? null : "Off by choice");
            }
            catch (Exception error) when (error is InvalidOperationException or UnauthorizedAccessException or System.Security.SecurityException or ArgumentException)
            {
                Mark(SetupStepId.StartAtLogin, SetupStatus.Failed, $"Couldn't write the Run key: {error.Message}");
                Go(current);
            }
        }, true), SkipButton(SetupStepId.StartAtLogin)));
    }

    // Step 7.
    private void Updates(StackPanel body)
    {
        body.Children.Add(UiKit.Text("Review how updates are checked. Updates come from github.com and are verified before they are installed.", 13, false, "TextPrimary", 8));
        var auto = UiKit.Radio("Check for updates automatically (daily)", "updates7", controller.Settings.UpdatesChoice != UpdatesChoice.Manual);
        var manual = UiKit.Radio("Only when I ask", "updates7", controller.Settings.UpdatesChoice == UpdatesChoice.Manual);
        body.Children.Add(auto);
        body.Children.Add(manual);
        body.Children.Add(UiKit.Row(UiKit.Button("Looks good", () =>
        {
            controller.ApplyUpdatesChoice(auto.IsChecked == true ? UpdatesChoice.Auto : UpdatesChoice.Manual);
            Finish(SetupStepId.Updates, SetupStatus.Passed);
        }, true), SkipButton(SetupStepId.Updates)));
    }

    // Step 8.
    private void Semantic(StackPanel body)
    {
        body.Children.Add(UiKit.Text("Semantic search finds notes by meaning as well as keywords. It is optional and nothing is downloaded here.", 13, false, "TextPrimary", 8));
        body.Children.Add(UiKit.Text($"To turn it on later, open the tray icon and choose Enable Semantic Search… It downloads about {ModelInstallException.FormatBytes(ModelManifest.Current.TotalDownloadBytes)} from huggingface.co.", 13, false, "TextPrimary", 8));
        body.Children.Add(UiKit.Row(UiKit.Button("Got it", () => Finish(SetupStepId.Semantic, SetupStatus.Passed), true), SkipButton(SetupStepId.Semantic)));
    }
}
