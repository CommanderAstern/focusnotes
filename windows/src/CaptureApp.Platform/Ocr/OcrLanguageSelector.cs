using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace CaptureApp.Platform.Ocr;

public sealed record OcrRecognizerModel(string Id, string[] Scripts, string[] Languages, string Url,
    string Revision, string Sha256, long Bytes, string DictUrl, string DictSha256, string License,
    string Kind = "recognizer");

public sealed record OcrLanguageSelection(OcrRecognizerModel Model, string PreferredLanguage, string MatchedLanguage,
    bool UsedFallback);

public static class OcrLanguageSelector
{
    private const uint MuiLanguageName = 0x8;

    public static OcrLanguageSelection Select(IEnumerable<string> preferredLanguages,
        IReadOnlyList<OcrRecognizerModel> models)
    {
        ArgumentNullException.ThrowIfNull(preferredLanguages);
        ArgumentNullException.ThrowIfNull(models);

        // When preferred languages map to several script groups, only the first supported preferred
        // language is used. This follows the Windows port decision recorded for the Swift multi-language rule.
        foreach (var preferred in preferredLanguages)
        {
            if (TryMatch(preferred, models, out var model, out var matchedLanguage))
            {
                return new OcrLanguageSelection(model, preferred, matchedLanguage, UsedFallback: false);
            }
        }

        if (TryMatch("en-US", models, out var englishModel, out var englishLanguage))
        {
            return new OcrLanguageSelection(englishModel, "en-US", englishLanguage, UsedFallback: true);
        }

        throw new InvalidOperationException("The OCR manifest must include a recognizer for en-US fallback.");
    }

    public static IReadOnlyList<string> GetPreferredLanguages()
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                uint languageCount = 0;
                uint bufferLength = 0;
                _ = GetUserPreferredUILanguages(MuiLanguageName, ref languageCount, null, ref bufferLength);
                if (bufferLength > 1)
                {
                    var buffer = new char[checked((int)bufferLength)];
                    if (GetUserPreferredUILanguages(MuiLanguageName, ref languageCount, buffer, ref bufferLength))
                    {
                        var languages = new string(buffer).Split('\0', StringSplitOptions.RemoveEmptyEntries);
                        if (languages.Length > 0)
                        {
                            return languages;
                        }
                    }
                }
            }
            catch (DllNotFoundException)
            {
                // The CurrentUICulture fallback also keeps this class usable in isolated test hosts.
            }
            catch (EntryPointNotFoundException)
            {
                // Older Windows versions may not expose the preferred-language API.
            }
        }

        var current = CultureInfo.CurrentUICulture.Name;
        return string.IsNullOrWhiteSpace(current) ? ["en-US"] : [current];
    }

    private static bool TryMatch(string preferred, IReadOnlyList<OcrRecognizerModel> models,
        out OcrRecognizerModel model, out string matchedLanguage)
    {
        var normalized = preferred.Trim().Replace('_', '-');
        foreach (var candidate in models)
        {
            var match = candidate.Languages.FirstOrDefault(language =>
                string.Equals(language, normalized, StringComparison.OrdinalIgnoreCase));
            if (match is not null)
            {
                model = candidate;
                matchedLanguage = match;
                return true;
            }
        }

        var languageCode = GetLanguageCode(normalized);
        if (languageCode.Length > 0)
        {
            foreach (var candidate in models)
            {
                var match = candidate.Languages.FirstOrDefault(language =>
                    string.Equals(GetLanguageCode(language), languageCode, StringComparison.OrdinalIgnoreCase));
                if (match is not null)
                {
                    model = candidate;
                    matchedLanguage = match;
                    return true;
                }
            }
        }

        model = null!;
        matchedLanguage = string.Empty;
        return false;
    }

    private static string GetLanguageCode(string language)
    {
        try
        {
            return CultureInfo.GetCultureInfo(language).TwoLetterISOLanguageName;
        }
        catch (CultureNotFoundException)
        {
            return language.Split('-', 2)[0];
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserPreferredUILanguages(uint flags, ref uint languageCount,
        [Out] char[]? languageBuffer, ref uint bufferLength);
}
