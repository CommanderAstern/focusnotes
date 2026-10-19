using CaptureApp.Platform.Ocr;
using Xunit;

namespace CaptureApp.Platform.Tests.Ocr;

public sealed class OcrLanguageSelectorTests
{
    [Fact]
    public void FirstPreferredSupportedLanguageChoosesOneRecognizerForItsScriptGroup()
    {
        using var latinFirst = new RapidOcrEngine(["fr-FR", "ko-KR"]);
        using var koreanFirst = new RapidOcrEngine(["ko-KR", "fr-FR"]);

        Assert.Equal("ppocrv5-latin-mobile", latinFirst.LanguageSelection.Model.Id);
        Assert.Equal("fr-FR", latinFirst.LanguageSelection.MatchedLanguage);
        Assert.Equal("ppocrv5-korean-mobile", koreanFirst.LanguageSelection.Model.Id);
        Assert.Equal("ko-KR", koreanFirst.LanguageSelection.MatchedLanguage);
    }

    [Fact]
    public void UnsupportedPreferredLanguageFallsBackToEnglishOnTheChineseRecognizer()
    {
        using var engine = new RapidOcrEngine(["he-IL"]);

        Assert.True(engine.LanguageSelection.UsedFallback);
        Assert.Equal("en-US", engine.LanguageSelection.MatchedLanguage);
        Assert.Equal("ppocrv5-ch-mobile", engine.LanguageSelection.Model.Id);
    }
}
