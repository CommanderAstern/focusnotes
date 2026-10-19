using System.Diagnostics;
using System.IO;
using System.Text.Json;
using CaptureApp.Platform.Ocr;
using Xunit;

namespace CaptureApp.Platform.Tests.Ocr;

// Runs alone so the latency gate is not measured against other test classes competing for CPU.
[CollectionDefinition("OcrFixtures", DisableParallelization = true)]
public sealed class OcrFixtureCollection;

[Collection("OcrFixtures")]
public sealed class OcrFixtureTests
{
    [Fact]
    [Trait("Needs", "OcrModels")]
    public void ParagraphAndCodeFixturesMatchTheCaptureChecksAssertions()
    {
        using var engine = CreateEngineAndRequireModels();
        var fixtures = Path.Combine(FindRepositoryRoot(), "conformance", "ocr", "fixtures");

        var paragraph = engine.Recognize(File.ReadAllBytes(Path.Combine(fixtures, "paragraph.png")),
            TestContext.Current.CancellationToken);
        var normalizedParagraph = paragraph.Text.ToLowerInvariant();
        var capture = normalizedParagraph.IndexOf("capture", StringComparison.Ordinal);
        var mountain = normalizedParagraph.IndexOf("mountain", StringComparison.Ordinal);
        Assert.True(capture >= 0 && mountain > capture, paragraph.Text);
        Assert.Contains("\n\n", paragraph.Text);

        var code = engine.Recognize(File.ReadAllBytes(Path.Combine(fixtures, "code.png")),
            TestContext.Current.CancellationToken);
        Assert.Contains("CaptureRecord", code.Text, StringComparison.Ordinal);
        Assert.Contains("collectRecords", code.Text, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("diagram.png")]
    [InlineData("gradient.png")]
    [InlineData("table.png")]
    [Trait("Needs", "OcrModels")]
    public void DiagramGradientAndTableFixturesStayImages(string fixtureName)
    {
        using var engine = CreateEngineAndRequireModels();
        var path = Path.Combine(FindRepositoryRoot(), "conformance", "ocr", "fixtures", fixtureName);

        var result = engine.Recognize(File.ReadAllBytes(path), TestContext.Current.CancellationToken);

        Assert.Equal(CaptureDecision.Image, CaptureClassifier.Classify(result).Decision);
    }

    [Fact]
    [Trait("Needs", "OcrModels")]
    public void EmptyFixtureStaysImageWithZeroCoverage()
    {
        using var engine = CreateEngineAndRequireModels();
        var path = Path.Combine(FindRepositoryRoot(), "conformance", "ocr", "fixtures", "empty.png");

        var result = engine.Recognize(File.ReadAllBytes(path), TestContext.Current.CancellationToken);

        Assert.Empty(result.Lines);
        Assert.Equal(0.0, result.Coverage);
        Assert.Equal(CaptureDecision.Image, CaptureClassifier.Classify(result).Decision);
    }

    [Fact]
    [Trait("Needs", "OcrModels")]
    [Trait("Category", "Perf")]
    public void LargeCorpusImageRecognitionHasP95BelowTheClassificationBudget()
    {
        using var engine = CreateEngineAndRequireModels();
        var corpus = Path.Combine(FindRepositoryRoot(), "conformance", "ocr", "corpus");
        using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(corpus, "manifest.json")));
        var files = new List<string>();
        foreach (var entry in manifest.RootElement.EnumerateArray())
        {
            var imagePath = Path.Combine(corpus, entry.GetProperty("file").GetString()!);
            using var bitmap = SkiaSharp.SKBitmap.Decode(imagePath);
            if (bitmap is { Width: 1920, Height: 1080 })
            {
                files.Add(imagePath);
            }
        }

        Assert.NotEmpty(files);
        _ = engine.Recognize(File.ReadAllBytes(files[0]), TestContext.Current.CancellationToken);
        var measurements = new List<double>(files.Count);
        foreach (var file in files)
        {
            var png = File.ReadAllBytes(file);
            var timer = Stopwatch.StartNew();
            _ = engine.Recognize(png, TestContext.Current.CancellationToken);
            timer.Stop();
            measurements.Add(timer.Elapsed.TotalMilliseconds);
        }

        measurements.Sort();
        var p95 = measurements[(int)Math.Ceiling(measurements.Count * 0.95) - 1];
        Assert.True(p95 <= 1500, $"OCR p95 was {p95:F1} ms for {measurements.Count} 1920×1080 corpus images.");
    }

    private static RapidOcrEngine CreateEngineAndRequireModels()
    {
        var engine = new RapidOcrEngine(["en-US"]);
        if (engine.IsAvailable)
        {
            return engine;
        }

        var reason = engine.MissingModelReason;
        engine.Dispose();
        if (Environment.GetEnvironmentVariable("CAPTUREAPP_REQUIRE_OCR_MODELS") == "1")
        {
            Assert.Fail(reason);
        }

        Assert.Skip(reason);
        throw new InvalidOperationException("Assert.Skip should have stopped the test.");
    }

    private static string FindRepositoryRoot()
    {
        foreach (var startingDirectory in new[] { Environment.CurrentDirectory, AppContext.BaseDirectory })
        {
            var directory = new DirectoryInfo(startingDirectory);
            while (directory is not null)
            {
                if (Directory.Exists(Path.Combine(directory.FullName, "conformance", "ocr", "fixtures")))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }
        }

        throw new DirectoryNotFoundException("Could not locate the repository conformance/ocr directory.");
    }
}
