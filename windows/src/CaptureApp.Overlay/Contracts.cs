using System.Windows.Media;

namespace CaptureApp.Overlay;

public enum ToastStyle { Success, Warning, Session, Copied }
public sealed record ToastHint(string Key, string Label = "");
public sealed record Toast(ToastStyle Style, string Title, string? Subtitle = null, ToastHint? Hint = null, double? Duration = null)
{
    public double DurationSeconds => Duration ?? (Style == ToastStyle.Warning ? Tokens.WarningToastDuration : Tokens.DefaultToastDuration);
}
public sealed record Suggestion(string Title, string? Secondary = null, string? SymbolName = null, string? Value = null);
/// <summary>Ranges are UTF-16 offsets, matching the Swift NSRange contract.</summary>
public readonly record struct TextMatch(int Start, int Length);
public enum SearchRowKind { Text, Image, Note }
public sealed record SearchRow(string Id, string Title, string Snippet = "", string Meta = "", SearchRowKind Kind = SearchRowKind.Text,
    IReadOnlyList<TextMatch>? TitleMatches = null, IReadOnlyList<TextMatch>? SnippetMatches = null,
    Func<CancellationToken, Task<ImageSource?>>? ThumbnailLoader = null);
public sealed record SearchSection(string Title, IReadOnlyList<SearchRow> Rows, string? ErrorMessage = null);
public enum SearchAction { Primary, Open, Reveal }
public sealed record SearchActions(Action<SearchRow> Primary, Action<SearchRow> Open, Action<SearchRow> Reveal,
    Action? OnClose = null, Func<SearchRow, SearchAction, Action?>? Freeze = null);
public sealed record InputRequest(string Placeholder, Func<string, IReadOnlyList<Suggestion>> Suggestions,
    Action<string> OnSubmit, Action OnCancel, string InitialText = "", string? Title = null, string? Secondary = null,
    bool SelectionOnly = false, Action<string>? OnAccept = null);

// Stable UI-only contracts for the cards in step 6b, mirroring NoteContracts.swift.
public enum NoteActionId { NewNote, Browse, Pin, OpenAsNote, CopyMarkdown, DiscardDraft }
public sealed record BrowseItem(string Id, string Title, string Detail, string SymbolName, bool IsPinned);
public enum BrowseChoice { Write, Open, Reveal }
