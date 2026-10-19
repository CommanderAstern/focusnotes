using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CaptureApp.Overlay;

namespace CaptureApp.Gallery;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(app.Dispatcher));
        using var theme = new ThemeManager(app.Resources);
        var exitCode = 0;
        app.Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                if (args is ["--check", var directory])
                {
                    await Check(directory, theme);
                    app.Shutdown();
                }
                else if (args is ["--live", var component]) Live(component, app);
                else throw new ArgumentException("Usage: CaptureApp.Gallery --check <outdir> | --live <toast|success|warning|session|copied|search|input|subheading|session-picker>");
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(exception); exitCode = 1;
                if (args is ["--check", var directory])
                {
                    Directory.CreateDirectory(directory);
                    await File.WriteAllTextAsync(Path.Combine(directory, "failure.txt"), exception.ToString());
                }
                app.Shutdown(1);
            }
        });
        app.Run();
        return exitCode;
    }
    private static async Task Check(string directory, ThemeManager theme)
    {
        Directory.CreateDirectory(directory);
        CheckGeometry();
        var files = new List<string>();
        foreach (var dark in new[] { false, true })
        {
            theme.Apply(dark, false);
            foreach (var scale in new[] { Tokens.One, Tokens.GalleryScale })
            {
                foreach (var fixture in Fixtures.All())
                {
                    var surface = fixture.Create();
                    try
                    {
                        if (surface is SearchPanelView search) await search.WaitForThumbnailsAsync();
                        var root = OverlaySurface.Frame(surface);
                        VisualTreeHelper.SetRootDpi(root, new DpiScale(scale, scale));
                        var size = new Size(surface.Width + Tokens.ShadowMargin * 2, surface.Height + Tokens.ShadowMargin * 2);
                        root.Measure(size); root.Arrange(new Rect(size)); root.UpdateLayout();
                        // Flush layout callbacks, including the absolute result-row layout, without creating an HWND.
                        await root.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Loaded);
                        root.UpdateLayout();
                        Require(Math.Abs(surface.Width - fixture.Width) < Tokens.LayoutTolerance, fixture.Name + ": visible width");
                        Require(Math.Abs(surface.Height - fixture.Height) < Tokens.LayoutTolerance, fixture.Name + ": visible height");
                        CheckLayout(root, fixture.Name);
                        var name = $"{fixture.Name}-{(dark ? "dark" : "light")}-{scale.ToString("0", CultureInfo.InvariantCulture)}x.png";
                        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width * scale), (int)Math.Ceiling(size.Height * scale), Tokens.RenderDpi * scale, Tokens.RenderDpi * scale, PixelFormats.Pbgra32);
                        bitmap.Render(root);
                        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                        using (var output = File.Create(Path.Combine(directory, name))) encoder.Save(output);
                        Require(bitmap.PixelWidth == (int)Math.Ceiling(size.Width * scale) && bitmap.PixelHeight == (int)Math.Ceiling(size.Height * scale), name + ": bitmap scale");
                        files.Add(name);
                    }
                    finally { (surface as IDisposable)?.Dispose(); }
                }
            }
        }
        theme.Apply(false, true);
        var highContrast = new SearchPanelView();
        var hcRoot = OverlaySurface.Frame(highContrast);
        hcRoot.Measure(new Size(hcRoot.Width, hcRoot.Height)); hcRoot.Arrange(new Rect(new Size(hcRoot.Width, hcRoot.Height))); hcRoot.UpdateLayout();
        Require(Equals(highContrast.FindResource("SurfaceTint"), SystemColors.WindowBrush), "High contrast uses system surface");
        Require(highContrast.TryFindResource("SurfaceShadow") is null, "High contrast disables shadow");
        highContrast.Dispose();
        theme.Apply(false, false);
        await File.WriteAllLinesAsync(Path.Combine(directory, "states.txt"), files);
        await File.WriteAllTextAsync(Path.Combine(directory, "checks.txt"), $"PASS: {files.Count} PNGs; token geometry, 100%/200% raster size, text DesiredSize/bounds, high contrast, and position round trips. No windows created.\nFocus integration gates require the Windows UI harness (§3b-2).\n");
        Console.WriteLine($"Gallery passed: {files.Count} PNGs in {directory}");
    }
    private static void CheckLayout(FrameworkElement root, string state)
    {
        foreach (var element in Descendants(root).OfType<FrameworkElement>())
        {
            if (element.Visibility != Visibility.Visible) continue;
            Require(double.IsFinite(element.ActualWidth) && double.IsFinite(element.ActualHeight), state + ": finite layout");
            Require(element.DesiredSize.Width <= element.ActualWidth + element.Margin.Left + element.Margin.Right + Tokens.LayoutTolerance && element.DesiredSize.Height <= element.ActualHeight + element.Margin.Top + element.Margin.Bottom + Tokens.LayoutTolerance, $"{state}: {element.GetType().Name} DesiredSize {element.DesiredSize} exceeds bounds {element.ActualWidth} × {element.ActualHeight}");
            if (element is not TextBlock text || string.IsNullOrEmpty(text.Text)) continue;
            var natural = new TextBlock
            {
                Text = text.Text, FontFamily = text.FontFamily, FontSize = text.FontSize, FontWeight = text.FontWeight,
                FontStyle = text.FontStyle, FontStretch = text.FontStretch, LineHeight = text.LineHeight,
                LineStackingStrategy = text.LineStackingStrategy, TextWrapping = TextWrapping.NoWrap
            };
            VisualTreeHelper.SetRootDpi(natural, VisualTreeHelper.GetDpi(root));
            natural.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            Require(natural.DesiredSize.Width <= text.ActualWidth + Tokens.LayoutTolerance && natural.DesiredSize.Height <= text.ActualHeight + Tokens.LayoutTolerance, $"{state}: text '{text.Text}' needs {natural.DesiredSize}, has {text.ActualWidth} × {text.ActualHeight}");
        }
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        if (root is FrameworkElement { Visibility: not Visibility.Visible }) yield break;
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
    private static void CheckGeometry()
    {
        // Negative origins and different work-area sizes exercise persistence independently of a desktop.
        foreach (var work in new[] { new Rect(-1920, 40, 1920, 1040), new Rect(0, 0, 1280, 720), new Rect(2560, -300, 1920, 1080) })
        {
            var size = new Size(Tokens.InputWidth, Tokens.InputFieldHeight + Tokens.Padding * 2);
            var rect = PanelGeometry.Default(size, work, true);
            Require(Math.Abs(rect.Top - (work.Top + work.Height * Tokens.PanelTopFraction)) < Tokens.LayoutTolerance, "Panel top fraction");
            var point = PanelGeometry.TopCenter(rect, work);
            Require(Math.Abs(point.Y - (Tokens.One - Tokens.PanelTopFraction)) < Tokens.LayoutTolerance, "Stored Y is measured from work-area bottom");
            var restored = PanelGeometry.FromPosition(point, size, work);
            Require(Math.Abs(restored.X - rect.X) < Tokens.LayoutTolerance && Math.Abs(restored.Y - rect.Y) < Tokens.LayoutTolerance && restored.Size == rect.Size, "Position round trip");
            var toast = PanelGeometry.Default(new Size(Tokens.ToastMinWidth, Tokens.ToastHeight), work, false);
            Require(Math.Abs(work.Bottom - toast.Bottom - Tokens.ToastBottomOffset) < Tokens.LayoutTolerance, "Toast bottom offset");
            var resized = PanelGeometry.Resize(rect, new Size(Tokens.SearchWidth, size.Height), work);
            Require(resized.Top == rect.Top && Math.Abs(resized.Left + resized.Width / 2 - (rect.Left + rect.Width / 2)) < Tokens.LayoutTolerance, "Resize keeps top and center");
        }
        var store = new MemoryPanelPositionStore();
        store.Save(PanelGeometry.NotePositionKey, new PanelPosition(Tokens.Center, Tokens.PanelTopFraction));
        Require(store.Load(PanelGeometry.NotePositionKey) == new PanelPosition(Tokens.Center, Tokens.PanelTopFraction), "Position store contract");
        Require(new Toast(ToastStyle.Warning, "Warning").DurationSeconds == Tokens.WarningToastDuration && new Toast(ToastStyle.Success, "Saved").DurationSeconds == Tokens.DefaultToastDuration, "Toast durations");
    }
    private static object? liveController;
    private static void Live(string component, Application app)
    {
        void Finish() { liveController = null; app.Shutdown(); }
        switch (component)
        {
            case "toast": case "success": case "warning": case "session": case "copied":
                var toast = new ToastController { OnExpire = Finish }; liveController = toast;
                var style = Enum.TryParse<ToastStyle>(component, true, out var parsed) ? parsed : ToastStyle.Success;
                toast.Show(new Toast(style, "Capture saved", "Added to System Design", new ToastHint("Alt+Shift+C", "name"))); break;
            case "search":
                var search = new SearchPanelController(); liveController = search;
                search.Present((text, _) => Task.FromResult<IReadOnlyList<SearchSection>>(text.Length == 0 ? Fixtures.Recent : Fixtures.Matches.Where(s => s.Rows.Any(r => r.Title.Contains(text, StringComparison.OrdinalIgnoreCase))).ToArray()),
                    new SearchActions(_ => Finish(), _ => Finish(), _ => Finish(), Finish)); break;
            case "input": case "subheading":
                var input = new InputPanelController(); liveController = input;
                input.Present(new InputRequest(component == "subheading" ? "Subheading" : "Name this session", text => Fixtures.Suggestions.Where(s => s.Title.StartsWith(text, StringComparison.OrdinalIgnoreCase)).ToArray(), _ => Finish(), Finish,
                    Title: component == "subheading" ? "Add subheading" : null, Secondary: component == "subheading" ? "In System Design" : null)); break;
            case "session-picker":
                var picker = new SessionPickerController(); liveController = picker; picker.Present(Fixtures.Sessions, _ => Finish(), Finish); break;
            default: throw new ArgumentException("Unknown component: " + component);
        }
    }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
