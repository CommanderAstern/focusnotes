using System.IO;
using CaptureApp.App;
using CaptureApp.AppCore.Shell;
using CaptureApp.Overlay;
using Xunit;

namespace CaptureApp.App.Tests;

public sealed class WiringTests
{
    [Fact]
    public void ToastMappingKeepsStyleTextAndHint()
    {
        var toast = UiHost.Map(new AppToast(AppToastStyle.Warning, "Title", "Sub", "Ctrl+Q", "choose note", 6));
        Assert.Equal(ToastStyle.Warning, toast.Style);
        Assert.Equal("Title", toast.Title);
        Assert.Equal("Sub", toast.Subtitle);
        Assert.Equal(new ToastHint("Ctrl+Q", "choose note"), toast.Hint);
        Assert.Equal(6, toast.DurationSeconds);
        Assert.Null(UiHost.Map(new AppToast(AppToastStyle.Success, "x")).Hint);
    }

    [Fact]
    public void PanelPositionsPersistInTheSettingsSection()
    {
        var path = Path.Combine(Path.GetTempPath(), "captureapp-app-tests-" + Guid.NewGuid().ToString("N"), "settings.json");
        try
        {
            var store = new SettingsPanelPositionStore(new SettingsStore(path));
            Assert.Null(store.Load("k"));
            store.Save("k", new PanelPosition(0.5, 0.25));
            store.Save("bad", new PanelPosition(double.NaN, 1));
            Assert.Equal(new PanelPosition(0.5, 0.25), new SettingsPanelPositionStore(new SettingsStore(path)).Load("k"));
            Assert.Null(store.Load("bad"));
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, true);
        }
    }

    [Fact]
    public void ModelsAreReportedInstalledOnlyWhenEveryFileExists()
    {
        var directory = Path.Combine(Path.GetTempPath(), "captureapp-app-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            Assert.False(AppController.ModelsInstalled(directory));
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }
}

public sealed class ForegroundTrackerTests
{
    [Theory]
    [InlineData("Shell_TrayWnd", true)]
    [InlineData("Shell_SecondaryTrayWnd", true)]
    [InlineData("NotifyIconOverflowWindow", true)]
    [InlineData("TopLevelWindowForOverflowXamlIsland", true)]
    [InlineData("Progman", true)]
    [InlineData("WorkerW", true)]
    [InlineData("Notepad", false)]
    [InlineData("Chrome_WidgetWin_1", false)]
    [InlineData(null, false)]
    public void ShellClassesAreNeverCaptureTargets(string? className, bool isShell) =>
        Assert.Equal(isShell, ForegroundTracker.IsShellClass(className));
}
