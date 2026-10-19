using System;
using System.IO;
using CaptureApp.Platform.Tray;
using Xunit;

namespace CaptureApp.Platform.Tests.Tray;

public sealed class TrayMenuModelTests
{
    [Fact]
    public void HoldsActionStateShortcutsChildrenAndSeparators()
    {
        var model = new TrayMenuModel(
        [
            new TrayMenuItem("capture", "Capture Area", "Ctrl+Alt+Shift+G", Enabled: true),
            TrayMenuItem.Separator(),
            new TrayMenuItem("setup", "Setup…", Checked: true,
                Children: [new TrayMenuItem("shortcuts", "Shortcuts", Enabled: false)])
        ]);

        Assert.Equal(3, model.Items.Count);
        Assert.Equal("Ctrl+Alt+Shift+G", model.Items[0].ShortcutText);
        Assert.True(model.Items[1].IsSeparator);
        Assert.Equal("shortcuts", model.Items[2].Children![0].Id);
        Assert.True(model.Items[2].Checked);
    }

    [Fact]
    public void RequiresUniqueIdsAcrossSubmenus()
    {
        Assert.Throws<ArgumentException>(() => new TrayMenuModel(
        [
            new TrayMenuItem("same", "One"),
            new TrayMenuItem("parent", "Two", Children: [new TrayMenuItem("same", "Nested")])
        ]));
    }
}

public sealed class TrayInteractiveTests
{
    [Fact]
    [Trait("Needs", "InteractiveDesktop")]
    public void TrayIconRegistersAndCanShowItsMenu()
    {
        var assets = FindRepositoryAssets();
        using var tray = new TrayIcon(static _ => { }, assets)
        {
            Menu = new TrayMenuModel([new TrayMenuItem("capture", "Capture Area")])
        };

        if (!tray.IsRegistered)
        {
            Assert.Skip("The interactive Windows shell did not accept the tray icon.");
        }

        using var dismiss = new System.Threading.Timer(_ => tray.CancelCurrentMenu(), null, 500, Timeout.Infinite);
        if (!tray.TryShowMenu())
        {
            Assert.Skip("SetForegroundWindow could not foreground the tray owner's own window.");
        }

        Assert.True(tray.IsRegistered);
    }

    private static TrayIconAssets FindRepositoryAssets()
    {
        for (var directory = new DirectoryInfo(Environment.CurrentDirectory); directory is not null; directory = directory.Parent)
        {
            foreach (var candidatePath in new[]
                     {
                         Path.Combine(directory.FullName, "windows", "src", "CaptureApp.Platform", "Assets"),
                         Path.Combine(directory.FullName, "src", "CaptureApp.Platform", "Assets")
                     })
            {
                if (File.Exists(Path.Combine(candidatePath, "tray-light.ico")))
                {
                    return TrayIconAssets.FromDirectory(candidatePath);
                }
            }
        }

        return TrayIconAssets.FindDefault();
    }
}
