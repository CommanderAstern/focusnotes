using System.Windows;
using System.Windows.Media;
using CaptureApp.Overlay;

namespace CaptureApp.Gallery;

internal sealed record Fixture(string Name, Func<OverlaySurface> Create, double Width, double Height);
internal static class Fixtures
{
    internal static readonly Suggestion[] Suggestions = [
        new("System Design", "Session · Oct 9", "record.circle"), new("MLE Interview Prep", "Session · Oct 8", "record.circle"),
        new("Rate limiting", "Note · System Design", "doc.text"), new("Distributed systems", "Note · System Design", "doc.text")];
    internal static readonly Suggestion[] Sessions = [new("System Design", "Modified Oct 9 · /vault/one.md", "record.circle", "/vault/one.md"), new("System Design", "Modified Oct 8 · /vault/two.md", "record.circle", "/vault/two.md")];
    internal static readonly SearchSection[] Recent = [new("Recent", [
        new("system", "System Design", "Design a reliable notification service at scale.", "10:04 · Edge · System Design"),
        new("limits", "Rate limiting", "Token buckets allow controlled bursts of requests.", "09:58 · Edge · System Design"),
        new("diagram", "Service architecture", "Gateway, queue, and worker topology.", "09:51 · Photos · System Design", SearchRowKind.Image, ThumbnailLoader: _ => Task.FromResult<ImageSource?>(Thumbnail())),
        new("mle", "MLE Interview Prep", "Feature stores, evaluation, and serving latency.", "Yesterday · Notes · Interview Prep", SearchRowKind.Note),
        new("cache", "Caching patterns", "Cache aside with explicit invalidation boundaries.", "Yesterday · Edge · System Design"),
        new("queue", "Message queues", "At least once delivery needs idempotent consumers.", "Oct 9 · Edge · System Design")])];
    internal static readonly SearchSection[] Matches = [new("Captures", [
        new("limit", "Rate limiting", "A rate limit protects services from traffic spikes.", "10:04 · Edge · System Design", TitleMatches: [new(5, 5)], SnippetMatches: [new(7, 5)]),
        new("token", "Token bucket limits", "Set a limit per user, route, and time window.", "09:58 · Edge · System Design", TitleMatches: [new(13, 5)], SnippetMatches: [new(6, 5)])]),
        new("Notes", [new("note", "System Design", "Rate limiting: fixed windows versus token buckets.", "Oct 9 · System Design", SearchRowKind.Note, SnippetMatches: [new(5, 5)])])];
    internal static IEnumerable<Fixture> All()
    {
        foreach (var (style, title, subtitle, stem) in new[] {
            (ToastStyle.Success, "Capture saved", "Added to System Design", "success"),
            (ToastStyle.Warning, "Choose a destination", "Your capture is waiting for a note", "warning"),
            (ToastStyle.Session, "Session started", "MLE Interview Prep", "session"),
            (ToastStyle.Copied, "Copied to clipboard", "Ready to paste into your notes", "copied") })
        foreach (var hasSubtitle in new[] { false, true })
        foreach (var hasHint in new[] { false, true })
        {
            ToastView Create() => new(new Toast(style, title, hasSubtitle ? subtitle : null, hasHint ? new ToastHint("Alt+Shift+C", "name") : null));
            // Toast width follows measured text, within the token bounds.
            var sample = Create();
            yield return new Fixture($"toast-{stem}-{(hasSubtitle ? "subtitle" : "plain")}-{(hasHint ? "hint" : "no-hint")}", Create, sample.Width, Tokens.ToastHeight);
        }
        foreach (var (name, sections, query, selected, loading) in new (string, SearchSection[], string, int?, bool)[] {
            ("empty", [], "", null, false), ("loading", Recent, "distributed", null, true),
            ("recent", Recent, "", 0, false), ("matches", Matches, "limit", 0, false),
            ("results", Recent, "", null, false), ("selected-row", Recent, "", 2, false),
            ("no-results", [], "consistent hashing", null, false), ("error", [new("", [], "Search unavailable. Try again.")], "limit", null, false),
            ("max-results", [new("Recent", Enumerable.Range(0, Tokens.MaxResults + 2).Select(i => new SearchRow(i.ToString(), "Result " + i, "A captured thought.", "Today · System Design")).ToArray())], "", 0, false) })
        {
            SearchPanelView Create() { var view = new SearchPanelView(query); view.Update(sections, selected); view.SetLoading(loading, animate: false); return view; }
            var remaining = Tokens.MaxResults; double listHeight = Tokens.Zero;
            foreach (var section in sections) { if (remaining == 0 || section.Rows.Count == 0) continue; var count = Math.Min(remaining, section.Rows.Count); remaining -= count; listHeight += Tokens.HeaderHeight + count * Tokens.ResultHeight; }
            if (listHeight == 0) listHeight = Tokens.NoResultsHeight;
            yield return new Fixture("search-" + name, Create, Tokens.SearchWidth, Tokens.Padding * 2 + Tokens.SearchFieldHeight + Tokens.BorderWidth * 2 + listHeight + Tokens.FooterHeight);
        }
        yield return Input("input-empty", "Name this session", "", [], null);
        yield return Input("input-suggestions", "Name this session", "System", Suggestions, null);
        yield return Input("input-selected", "Name this session", "System", Suggestions, 0);
        yield return Input("input-subheading", "Subheading", "", [], null, "Add subheading", "In System Design");
        yield return Input("input-max-suggestions", "Name this session", "", Suggestions.Concat(Suggestions).ToArray(), 0);
        yield return Input("session-picker", "Select a session…", "", Sessions, null, "Multiple sessions found with the given name");
        yield return Input("session-picker-selected", "Select a session…", "", Sessions, 0, "Multiple sessions found with the given name");
        yield return Input("session-picker-empty", "Select a session…", "zzz", [], null, "Multiple sessions found with the given name");
    }
    private static Fixture Input(string name, string placeholder, string text, Suggestion[] suggestions, int? selected, string? title = null, string? secondary = null) => new(name,
        () => new InputPanelView(placeholder, text, suggestions, selected, title, secondary), Tokens.InputWidth,
        Tokens.Padding * 2 + Tokens.InputFieldHeight + (title is null ? Tokens.Zero : Tokens.HeaderHeight) + (secondary is null ? Tokens.Zero : Tokens.MetaLineHeight + Tokens.Padding / 2) + (suggestions.Length == 0 ? Tokens.Zero : Tokens.BorderWidth + Math.Min(suggestions.Length, Tokens.MaxSuggestions) * Tokens.SuggestionHeight));
    private static DrawingImage Thumbnail()
    {
        var group = new DrawingGroup();
        group.Children.Add(new GeometryDrawing(SystemColors.HighlightBrush, null, new RectangleGeometry(new Rect(Tokens.Zero, Tokens.Zero, Tokens.ThumbnailSize, Tokens.ThumbnailSize), Tokens.ThumbnailRadius, Tokens.ThumbnailRadius)));
        group.Children.Add(new GeometryDrawing(SystemColors.HighlightTextBrush, null, new EllipseGeometry(new Point(Tokens.ThumbnailSize / 2, Tokens.ThumbnailSize / 2), Tokens.ThumbnailSize / 4, Tokens.ThumbnailSize / 4)));
        var image = new DrawingImage(group); image.Freeze(); return image;
    }
}
