using System.Diagnostics;
using System.Text.Json;
using RapidOcrNet;
using SkiaSharp;

namespace CaptureApp.Platform.Ocr;

/// <summary>Offline RapidOcrNet engine with one lazily created warm model session per recognizer.</summary>
public sealed class RapidOcrEngine : IOcrEngine, IDisposable
{
    private static readonly TimeSpan IdleLifetime = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan EvictionPeriod = TimeSpan.FromSeconds(10);
    private const string DetectorFile = "ppocrv5-det-mobile.onnx";
    private const string ClassifierFile = "ppocrv5-textline-cls-mobile.onnx";
    private static readonly string[] RightToLeftLanguages = ["ar-SA", "ars-SA"];

    private readonly object _gate = new();
    private readonly Dictionary<string, ModelSlot> _loadedModels = new(StringComparer.Ordinal);
    private readonly IReadOnlyList<OcrRecognizerModel> _models;
    private readonly OcrLanguageSelection _selection;
    private readonly string _recognizerDirectory;
    private readonly System.Threading.Timer _evictionTimer;
    private bool _disposed;

    public RapidOcrEngine(IEnumerable<string>? preferredLanguages = null)
    {
        _models = LoadManifest();
        _selection = OcrLanguageSelector.Select(preferredLanguages ?? OcrLanguageSelector.GetPreferredLanguages(), _models);
        _recognizerDirectory = Path.Combine(AppContext.BaseDirectory, "OcrModels");
        _evictionTimer = new System.Threading.Timer(EvictIdleModels, null, EvictionPeriod, EvictionPeriod);
    }

    public OcrLanguageSelection LanguageSelection => _selection;

    public bool IsAvailable => GetMissingModelFiles().Count == 0;

    public string MissingModelReason
    {
        get
        {
            var missing = GetMissingModelFiles();
            return missing.Count == 0
                ? string.Empty
                : $"OCR models missing: {string.Join(", ", missing)}. Fetch them with windows/scripts/fetch-ocr-models.sh or .ps1.";
        }
    }

    public OcrResult Recognize(byte[] png, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(png);
        cancellationToken.ThrowIfCancellationRequested();
        using var bitmap = SKBitmap.Decode(png);
        if (bitmap is null || bitmap.Width <= 0 || bitmap.Height <= 0)
        {
            throw new InvalidDataException("The input is not a decodable PNG image.");
        }

        return Recognize(bitmap, cancellationToken);
    }

    public OcrResult Recognize(SKBitmap bitmap, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(bitmap);
        cancellationToken.ThrowIfCancellationRequested();
        EnsureAvailable();

        var slot = AcquireSlot(_selection.Model);
        var acquired = false;
        try
        {
            slot.Gate.Wait(cancellationToken);
            acquired = true;
            ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed), this);

            var recognized = slot.Ocr.DetectAsync(bitmap, RapidOcrOptions.Default, progress: null,
                    cancellationToken: cancellationToken)
                .ConfigureAwait(false).GetAwaiter().GetResult();
            cancellationToken.ThrowIfCancellationRequested();
            var lines = recognized.TextBlocks
                .Where(block => !string.IsNullOrWhiteSpace(block.Text))
                .Select(block => ToLine(block.Text, block.BoxPoints, block.CharScores, bitmap.Width, bitmap.Height))
                .ToArray();
            var orderedLines = OcrTextLayout.ReadingOrder(lines);
            var text = OcrTextLayout.JoinText(orderedLines);
            var coverage = CaptureClassifier.Classify(lines, bitmap.Width, bitmap.Height).Metrics.TextCoverage;
            return new OcrResult(text, orderedLines, coverage, bitmap.Width, bitmap.Height);
        }
        finally
        {
            if (acquired)
            {
                slot.Gate.Release();
            }

            ReleaseSlot(slot);
        }
    }

    public void Dispose()
    {
        ModelSlot[] slots;
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            Volatile.Write(ref _disposed, true);
            _evictionTimer.Dispose();
            while (_loadedModels.Values.Any(slot => slot.Leases > 0))
            {
                Monitor.Wait(_gate);
            }

            slots = _loadedModels.Values.ToArray();
            _loadedModels.Clear();
        }

        foreach (var slot in slots)
        {
            slot.Ocr.Dispose();
            slot.Gate.Dispose();
        }
    }

    private ModelSlot AcquireSlot(OcrRecognizerModel model)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (!_loadedModels.TryGetValue(model.Id, out var slot))
            {
                slot = CreateSlot(model);
                _loadedModels.Add(model.Id, slot);
            }

            slot.Leases++;
            return slot;
        }
    }

    private void ReleaseSlot(ModelSlot slot)
    {
        lock (_gate)
        {
            slot.LastUsedTimestamp = Stopwatch.GetTimestamp();
            slot.Leases--;
            Monitor.PulseAll(_gate);
        }
    }

    private ModelSlot CreateSlot(OcrRecognizerModel model)
    {
        var detectorPath = Path.Combine(_recognizerDirectory, DetectorFile);
        var classifierPath = Path.Combine(_recognizerDirectory, ClassifierFile);
        var recognizerPath = Path.Combine(_recognizerDirectory, $"{model.Id}.onnx");
        var dictionaryPath = Path.Combine(_recognizerDirectory, $"{model.Id}.dict.txt");
        var ocr = new RapidOcr();
        try
        {
            var threads = Math.Min(4, Math.Max(1, Environment.ProcessorCount));
            using var sessionOptions = RapidOcr.GetDefaultSessionOptions(threads);
            ocr.InitModels(detectorPath, classifierPath, recognizerPath, dictionaryPath, sessionOptions);
            return new ModelSlot(ocr, Stopwatch.GetTimestamp());
        }
        catch
        {
            ocr.Dispose();
            throw;
        }
    }

    private void EvictIdleModels(object? state)
    {
        List<ModelSlot> expired = [];
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            var now = Stopwatch.GetTimestamp();
            foreach (var (modelId, slot) in _loadedModels.ToArray())
            {
                if (slot.Leases == 0 && Stopwatch.GetElapsedTime(slot.LastUsedTimestamp, now) >= IdleLifetime)
                {
                    _loadedModels.Remove(modelId);
                    expired.Add(slot);
                }
            }
        }

        foreach (var slot in expired)
        {
            slot.Ocr.Dispose();
            slot.Gate.Dispose();
        }
    }

    private void EnsureAvailable()
    {
        if (!IsAvailable)
        {
            throw new OcrModelsMissingException(MissingModelReason);
        }
    }

    private IReadOnlyList<string> GetMissingModelFiles()
    {
        var missing = new List<string>();
        var files = new[]
        {
            Path.Combine(_recognizerDirectory, DetectorFile),
            Path.Combine(_recognizerDirectory, ClassifierFile),
            Path.Combine(_recognizerDirectory, $"{_selection.Model.Id}.onnx"),
            Path.Combine(_recognizerDirectory, $"{_selection.Model.Id}.dict.txt")
        };
        foreach (var path in files)
        {
            if (!File.Exists(path))
            {
                missing.Add(Path.GetFileName(path));
            }
        }

        return missing;
    }

    private OcrLine ToLine(string text, IReadOnlyList<SKPointI> points, IReadOnlyList<float>? charScores,
        int imageWidth, int imageHeight)
    {
        if (points.Count == 0)
        {
            return new OcrLine(text, 0, 0, 0, 0, 0);
        }

        var minPixelX = points.Min(point => point.X);
        var maxPixelX = points.Max(point => point.X);
        var minPixelY = points.Min(point => point.Y);
        var maxPixelY = points.Max(point => point.Y);
        var lineText = RightToLeftLanguages.Contains(_selection.MatchedLanguage, StringComparer.Ordinal)
            ? OcrTextLayout.ReverseTextElements(text)
            : text;
        var confidence = charScores is { Count: > 0 } ? charScores.Average() : 0;
        return new OcrLine(lineText,
            (double)minPixelX / imageWidth,
            1.0 - (double)maxPixelY / imageHeight,
            (double)maxPixelX / imageWidth,
            1.0 - (double)minPixelY / imageHeight,
            confidence);
    }

    private static IReadOnlyList<OcrRecognizerModel> LoadManifest()
    {
        var resourceName = typeof(RapidOcrEngine).Assembly.GetManifestResourceNames()
            .SingleOrDefault(name => name.EndsWith("Ocr.ocr-models.json", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("The embedded OCR model manifest is missing.");
        using var stream = typeof(RapidOcrEngine).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("The embedded OCR model manifest could not be opened.");
        var entries = JsonSerializer.Deserialize<List<OcrRecognizerModel>>(stream,
                          new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                      ?? throw new InvalidDataException("The embedded OCR model manifest is empty.");
        // Detector and classifier entries share the manifest but are not language-selectable.
        return entries.Where(entry => entry.Kind == "recognizer").ToArray();
    }

    private sealed class ModelSlot(RapidOcr ocr, long lastUsedTimestamp)
    {
        public RapidOcr Ocr { get; } = ocr;
        public SemaphoreSlim Gate { get; } = new(1, 1);
        public long LastUsedTimestamp { get; set; } = lastUsedTimestamp;
        public int Leases { get; set; }
    }
}
