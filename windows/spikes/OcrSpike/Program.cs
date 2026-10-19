using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using RapidOcrNet;
using SkiaSharp;

internal static class Program
{
    private const double MinimumTextCoverage = 0.12;
    private const double DenseCropCoverage = 0.25;
    private const double MinimumMeanConfidence = 0.75;
    private const int MinimumLineCount = 4;
    private const double MaximumCerDeltaPoints = 2.0;
    private const double MaximumLargeImageP95Ms = 1500.0;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static async Task<int> Main(string[] args)
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        if (args.Length != 3)
        {
            Console.Error.WriteLine("Usage: OcrSpike <corpusdir> <mac-baseline.json> <out.md>");
            return 2;
        }

        try
        {
            return await RunAsync(args[0], args[1], args[2]);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"OcrSpike failed: {exception}");
            return 1;
        }
    }

    private static async Task<int> RunAsync(string corpusPath, string baselinePath, string reportPath)
    {
        var corpusDirectory = Path.GetFullPath(corpusPath);
        var repositoryRoot = FindRepositoryRoot(corpusDirectory);
        var baseline = JsonSerializer.Deserialize<MacBaseline>(File.ReadAllText(baselinePath), JsonOptions)
            ?? throw new InvalidDataException("The Mac baseline JSON is empty.");
        var manifest = JsonSerializer.Deserialize<List<ManifestItem>>(
            File.ReadAllText(Path.Combine(corpusDirectory, "manifest.json")), JsonOptions)
            ?? throw new InvalidDataException("The OCR corpus manifest is empty.");
        var modelSpecs = JsonSerializer.Deserialize<List<ModelSpec>>(
            File.ReadAllText(Path.Combine(repositoryRoot, "windows", "spikes", "ocr-models.json")), JsonOptions)
            ?? throw new InvalidDataException("The OCR model manifest is empty.");
        if (manifest.Count == 0)
        {
            throw new InvalidDataException("The OCR corpus contains no images.");
        }

        var macByFile = baseline.Images.ToDictionary(image => image.File, StringComparer.Ordinal);
        foreach (var item in manifest)
        {
            if (!macByFile.ContainsKey(item.File))
            {
                throw new InvalidDataException($"The Mac baseline is missing {item.File}.");
            }
        }

        var modelByLanguage = new Dictionary<string, ModelSpec>(StringComparer.Ordinal);
        foreach (var model in modelSpecs)
        {
            foreach (var language in model.Languages)
            {
                if (!modelByLanguage.TryAdd(language, model))
                {
                    throw new InvalidDataException($"More than one recognizer is mapped to {language}.");
                }
            }
        }

        var corpusLanguages = manifest.Select(item => item.Language).ToHashSet(StringComparer.Ordinal);
        var visionLanguages = baseline.SupportedRecognitionLanguages.ToHashSet(StringComparer.Ordinal);
        if (!corpusLanguages.SetEquals(visionLanguages))
        {
            var missing = visionLanguages.Except(corpusLanguages, StringComparer.Ordinal);
            var extra = corpusLanguages.Except(visionLanguages, StringComparer.Ordinal);
            throw new InvalidDataException($"Corpus languages must match Vision. Missing: {string.Join(", ", missing)}; extra: {string.Join(", ", extra)}.");
        }

        foreach (var language in visionLanguages)
        {
            if (!modelByLanguage.ContainsKey(language))
            {
                throw new InvalidDataException($"Vision language {language} has no recognizer mapping.");
            }
        }

        var modelCacheDirectory = Path.Combine(repositoryRoot, "windows", "spikes", ".models");
        Directory.CreateDirectory(modelCacheDirectory);
        using var httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("CaptureApp.OcrSpike/1.0");
        httpClient.DefaultRequestHeaders.Accept.ParseAdd("application/octet-stream");
        var downloadedModels = new Dictionary<string, DownloadedModel>(StringComparer.Ordinal);
        foreach (var model in modelSpecs)
        {
            var modelPath = await EnsureAssetAsync(httpClient, modelCacheDirectory, model.Id + ".onnx",
                model.Url, model.Sha256, model.Bytes);
            var dictionaryPath = await EnsureAssetAsync(httpClient, modelCacheDirectory, model.Id + ".dict.txt",
                model.DictUrl, model.DictSha256, expectedBytes: null);
            downloadedModels.Add(model.Id, new DownloadedModel(modelPath, dictionaryPath));
        }

        var modelDirectory = Path.Combine(AppContext.BaseDirectory, "models", "v5");
        var detectorPath = Path.Combine(modelDirectory, "ch_PP-OCRv5_mobile_det.onnx");
        var classifierPath = Path.Combine(modelDirectory, "ch_PP-LCNet_x0_25_textline_ori_cls_mobile.onnx");
        var measurements = new List<ImageMeasurement>(manifest.Count);
        FixtureReport? fixtureReport = null;
        foreach (var model in modelSpecs)
        {
            var entries = manifest.Where(item => string.Equals(modelByLanguage[item.Language].Id, model.Id,
                StringComparison.Ordinal)).ToList();
            if (entries.Count == 0)
            {
                continue;
            }

            var downloaded = downloadedModels[model.Id];
            using var ocr = new RapidOcr();
            ocr.InitModels(detectorPath, classifierPath, downloaded.ModelPath, downloaded.DictionaryPath);

            // One complete pass warms this model session and every PNG path in its language group.
            foreach (var item in entries)
            {
                _ = Recognize(ocr, Path.Combine(corpusDirectory, item.File), IsRightToLeftLanguage(item.Language));
            }

            foreach (var item in entries)
            {
                var path = Path.Combine(corpusDirectory, item.File);
                var (width, height) = ReadPngDimensions(path);
                var start = Stopwatch.GetTimestamp();
                var recognized = Recognize(ocr, path, IsRightToLeftLanguage(item.Language));
                var latencyMs = Stopwatch.GetElapsedTime(start).TotalMilliseconds;
                measurements.Add(new ImageMeasurement(item, macByFile[item.File], model.Id, recognized.Text,
                    recognized.Classification, width, height, latencyMs));
                Console.WriteLine($"{item.File} [{model.Id}]: {latencyMs:F1} ms");
            }

            if (model.Id == "ppocrv5-ch-mobile")
            {
                fixtureReport = RunFixtureAssertions(ocr,
                    Path.GetFullPath(Path.Combine(corpusDirectory, "..", "fixtures")));
            }
        }

        if (measurements.Count != manifest.Count || fixtureReport is null)
        {
            throw new InvalidDataException("Not every corpus image was measured or the English fixture model did not run.");
        }

        var modelSizes = modelSpecs.Select(spec => new ModelSize(
            spec.Id, spec.Revision, spec.Url, spec.License, spec.Bytes,
            new FileInfo(downloadedModels[spec.Id].DictionaryPath).Length,
            downloadedModels[spec.Id].ModelPath, downloadedModels[spec.Id].DictionaryPath)).ToList();
        var nativeRuntime = FindNativeRuntime();
        var groups = measurements.GroupBy(item => item.Manifest.Language, StringComparer.Ordinal)
            .OrderBy(group => group.Key, StringComparer.Ordinal)
            .Select(BuildLanguageReport).ToList();
        var corpusBytes = Directory.GetFiles(corpusDirectory, "*.png", SearchOption.AllDirectories)
            .Sum(file => new FileInfo(file).Length);
        var largeImages = measurements.Where(item => item.Width == 1920 && item.Height == 1080).ToList();
        var largeImageP95 = largeImages.Count == 0 ? double.NaN : Percentile(largeImages.Select(item => item.LatencyMs), 0.95);
        var macLargeImageP95 = largeImages.Count == 0 ? double.NaN : Percentile(largeImages.Select(item => item.Mac.LatencyMs), 0.95);
        var classifierAgreement = measurements.Count(item =>
                string.Equals(item.Mac.ClassifierDecision, item.Classification.Decision, StringComparison.Ordinal))
            / (double)measurements.Count;
        var corpusDisplayPath = Path.GetRelativePath(Environment.CurrentDirectory, corpusDirectory);

        var report = BuildReport(corpusDisplayPath, baseline, manifest.Count, corpusBytes,
            groups, classifierAgreement, largeImages.Count, macLargeImageP95, largeImageP95, fixtureReport,
            modelSizes, detectorPath, classifierPath, nativeRuntime);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(reportPath))!);
        File.WriteAllText(reportPath, report, new UTF8Encoding(false));
        Console.WriteLine($"Report written to {Path.GetFullPath(reportPath)}");

        var cerPass = groups.All(group => group.DeltaPoints <= MaximumCerDeltaPoints);
        var classifierPass = classifierAgreement >= 0.95;
        var latencyPass = largeImages.Count > 0 && largeImageP95 <= MaximumLargeImageP95Ms;
        return fixtureReport.AllPassed && cerPass && classifierPass && latencyPass ? 0 : 1;
    }

    private static RecognizedImage Recognize(RapidOcr ocr, string imagePath, bool reverseRightToLeft = false)
    {
        var result = ocr.Detect(imagePath, RapidOcrOptions.Default);
        var (imageWidth, imageHeight) = ReadPngDimensions(imagePath);
        var lines = result.TextBlocks
            .Where(block => !string.IsNullOrWhiteSpace(block.Text))
            .Select(block => ToOcrLine(reverseRightToLeft ? ReverseTextElements(block.Text) : block.Text,
                block.BoxPoints, block.CharScores, imageWidth, imageHeight))
            .ToList();
        var orderedLines = ReadingOrder(lines);
        var text = JoinText(orderedLines);
        var classification = Classify(lines);
        return new RecognizedImage(text, classification);
    }

    private static bool IsRightToLeftLanguage(string language) => language is "ar-SA" or "ars-SA";

    private static string ReverseTextElements(string text)
    {
        var starts = StringInfo.ParseCombiningCharacters(text);
        var output = new StringBuilder(text.Length);
        for (var index = starts.Length - 1; index >= 0; index--)
        {
            var end = index + 1 < starts.Length ? starts[index + 1] : text.Length;
            output.Append(text.AsSpan(starts[index], end - starts[index]));
        }

        return output.ToString();
    }

    private static OcrLine ToOcrLine(string text, IReadOnlyList<SKPointI> points, IReadOnlyList<float>? charScores,
        int imageWidth, int imageHeight)
    {
        if (points.Count == 0)
        {
            return new OcrLine(text, 0, 0, 0, 0, 0);
        }

        var minX = (double)points.Min(point => point.X) / imageWidth;
        var minPixelY = points.Min(point => point.Y);
        var maxPixelY = points.Max(point => point.Y);
        var minY = 1.0 - (double)maxPixelY / imageHeight;
        var maxY = 1.0 - (double)minPixelY / imageHeight;
        var maxX = (double)points.Max(point => point.X) / imageWidth;
        var confidence = charScores is { Count: > 0 } ? charScores.Average() : 0.0;
        return new OcrLine(text, minX, minY, maxX, maxY, confidence);
    }

    private static List<OcrLine> ReadingOrder(IReadOnlyCollection<OcrLine> lines)
    {
        var vertical = lines.OrderByDescending(line => line.MidY).ThenBy(line => line.MinX).ToList();
        var rows = new List<List<OcrLine>>();
        foreach (var line in vertical)
        {
            if (rows.Count > 0)
            {
                var anchor = rows[^1][0];
                if (Math.Abs(anchor.MidY - line.MidY) <= Math.Min(anchor.Height, line.Height) * 0.5)
                {
                    rows[^1].Add(line);
                    continue;
                }
            }

            rows.Add([line]);
        }

        return rows.SelectMany(row => row.OrderBy(line => line.MinX)).ToList();
    }

    private static string JoinText(IReadOnlyList<OcrLine> lines)
    {
        if (lines.Count == 0)
        {
            return string.Empty;
        }

        var heights = lines.Select(line => line.Height).Order().ToArray();
        var typicalHeight = heights[heights.Length / 2];
        var output = new StringBuilder();
        for (var index = 0; index < lines.Count; index++)
        {
            if (index > 0)
            {
                var previous = lines[index - 1];
                var current = lines[index];
                var verticalGap = previous.MinY - current.MaxY;
                output.Append(verticalGap > typicalHeight * 1.3 ? "\n\n" : "\n");
            }

            output.Append(lines[index].Text);
        }

        return output.ToString();
    }

    private static Classification Classify(IReadOnlyCollection<OcrLine> lines)
    {
        var usable = lines.Where(line => !string.IsNullOrWhiteSpace(line.Text)).ToArray();
        var coverage = usable.Sum(line =>
        {
            var width = Math.Min(1.0, line.MaxX) - Math.Max(0.0, line.MinX);
            var height = Math.Min(1.0, line.MaxY) - Math.Max(0.0, line.MinY);
            return width > 0 && height > 0 ? width * height : 0;
        });
        var meanConfidence = usable.Length == 0 ? 0.0 : usable.Average(line => line.Confidence);
        var isProse = coverage >= MinimumTextCoverage && usable.Length >= MinimumLineCount;
        var isDenseCrop = coverage >= DenseCropCoverage && usable.Length > 0;
        var decision = meanConfidence >= MinimumMeanConfidence && (isProse || isDenseCrop) ? "text" : "image";
        return new Classification(decision, coverage, meanConfidence, usable.Length);
    }

    private static FixtureReport RunFixtureAssertions(RapidOcr ocr, string fixtureDirectory)
    {
        var paragraph = Recognize(ocr, Path.Combine(fixtureDirectory, "paragraph.png")).Text;
        var paragraphLower = paragraph.ToLowerInvariant();
        var captureIndex = paragraphLower.IndexOf("capture", StringComparison.Ordinal);
        var mountainIndex = paragraphLower.IndexOf("mountain", StringComparison.Ordinal);
        var paragraphPassed = captureIndex >= 0 && mountainIndex >= 0 && captureIndex < mountainIndex
            && paragraph.Contains("\n\n", StringComparison.Ordinal);

        var code = Recognize(ocr, Path.Combine(fixtureDirectory, "code.png")).Text;
        var codePassed = code.Contains("CaptureRecord", StringComparison.Ordinal)
            && code.Contains("collectRecords", StringComparison.Ordinal);
        return new FixtureReport(paragraphPassed, codePassed, paragraph, code);
    }

    private static LanguageReport BuildLanguageReport(IGrouping<string, ImageMeasurement> group)
    {
        var items = group.ToList();
        var modelIds = items.Select(item => item.ModelId).Distinct(StringComparer.Ordinal).ToArray();
        if (modelIds.Length != 1)
        {
            throw new InvalidDataException($"Language {group.Key} was measured with more than one recognition model.");
        }

        var macCer = AggregateCer(items.Select(item => (item.Manifest.GroundTruth, item.Mac.Text)));
        var rapidCer = AggregateCer(items.Select(item => (item.Manifest.GroundTruth, item.RapidText)));
        var macP50 = Percentile(items.Select(item => item.Mac.LatencyMs), 0.50);
        var macP95 = Percentile(items.Select(item => item.Mac.LatencyMs), 0.95);
        var rapidP50 = Percentile(items.Select(item => item.LatencyMs), 0.50);
        var rapidP95 = Percentile(items.Select(item => item.LatencyMs), 0.95);
        var large = items.Where(item => item.Width == 1920 && item.Height == 1080).ToList();
        var macLargeP95 = large.Count == 0 ? double.NaN : Percentile(large.Select(item => item.Mac.LatencyMs), 0.95);
        var rapidLargeP95 = large.Count == 0 ? double.NaN : Percentile(large.Select(item => item.LatencyMs), 0.95);
        var agreement = items.Count(item => string.Equals(item.Mac.ClassifierDecision, item.Classification.Decision,
                StringComparison.Ordinal)) / (double)items.Count;
        return new LanguageReport(group.Key, modelIds[0], items.Count, macCer, rapidCer, (rapidCer - macCer) * 100.0,
            macP50, macP95, rapidP50, rapidP95, macLargeP95, rapidLargeP95, large.Count, agreement);
    }

    private static double AggregateCer(IEnumerable<(string Reference, string Hypothesis)> pairs)
    {
        long totalErrors = 0;
        long totalReferenceCharacters = 0;
        foreach (var (reference, hypothesis) in pairs)
        {
            var referenceRunes = Normalize(reference).EnumerateRunes().ToArray();
            var hypothesisRunes = Normalize(hypothesis).EnumerateRunes().ToArray();
            totalErrors += Levenshtein(referenceRunes, hypothesisRunes);
            totalReferenceCharacters += referenceRunes.Length;
        }

        return totalReferenceCharacters == 0 ? 0 : totalErrors / (double)totalReferenceCharacters;
    }

    private static string Normalize(string text)
    {
        var nfc = text.Normalize(NormalizationForm.FormC);
        return Regex.Replace(nfc, @"\s+", " ").Trim();
    }

    private static int Levenshtein<T>(IReadOnlyList<T> source, IReadOnlyList<T> target)
        where T : IEquatable<T>
    {
        var previous = Enumerable.Range(0, target.Count + 1).ToArray();
        var current = new int[target.Count + 1];
        for (var sourceIndex = 1; sourceIndex <= source.Count; sourceIndex++)
        {
            current[0] = sourceIndex;
            for (var targetIndex = 1; targetIndex <= target.Count; targetIndex++)
            {
                var substitution = previous[targetIndex - 1]
                    + (source[sourceIndex - 1].Equals(target[targetIndex - 1]) ? 0 : 1);
                current[targetIndex] = Math.Min(Math.Min(previous[targetIndex] + 1, current[targetIndex - 1] + 1), substitution);
            }

            (previous, current) = (current, previous);
        }

        return previous[target.Count];
    }

    private static double Percentile(IEnumerable<double> values, double percentile)
    {
        var ordered = values.Order().ToArray();
        if (ordered.Length == 0)
        {
            return double.NaN;
        }

        var index = Math.Clamp((int)Math.Ceiling(percentile * ordered.Length) - 1, 0, ordered.Length - 1);
        return ordered[index];
    }

    private static string FindRepositoryRoot(string corpusDirectory)
    {
        DirectoryInfo? directory = new(corpusDirectory);
        while (directory is not null)
        {
            var manifest = Path.Combine(directory.FullName, "windows", "spikes", "ocr-models.json");
            if (File.Exists(manifest))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException($"Could not locate windows/spikes/ocr-models.json above {corpusDirectory}.");
    }

    private static async Task<string> EnsureAssetAsync(HttpClient client, string cacheDirectory, string filename,
        string url, string expectedSha256, long? expectedBytes)
    {
        var target = Path.Combine(cacheDirectory, filename);
        if (File.Exists(target) && await AssetMatchesAsync(target, expectedSha256, expectedBytes))
        {
            return target;
        }

        if (File.Exists(target))
        {
            File.Delete(target);
        }

        var partial = target + ".partial";
        if (File.Exists(partial))
        {
            File.Delete(partial);
        }

        try
        {
            using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
            if (!response.IsSuccessStatusCode)
            {
                var detail = await response.Content.ReadAsStringAsync();
                throw new HttpRequestException($"Model server returned {(int)response.StatusCode} {response.ReasonPhrase} for {url}: {detail[..Math.Min(detail.Length, 300)]}");
            }
            await using (var destination = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                             128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                await response.Content.CopyToAsync(destination);
                await destination.FlushAsync();
            }

            if (!await AssetMatchesAsync(partial, expectedSha256, expectedBytes))
            {
                throw new InvalidDataException($"Downloaded model asset failed size/SHA-256 verification: {url}");
            }

            File.Move(partial, target, overwrite: true);
            return target;
        }
        catch
        {
            if (File.Exists(partial))
            {
                File.Delete(partial);
            }

            throw;
        }
    }

    private static async Task<bool> AssetMatchesAsync(string path, string expectedSha256, long? expectedBytes)
    {
        var info = new FileInfo(path);
        if (expectedBytes is not null && info.Length != expectedBytes.Value)
        {
            return false;
        }

        await using var stream = File.OpenRead(path);
        var digest = await SHA256.HashDataAsync(stream);
        var actual = Convert.ToHexString(digest).ToLowerInvariant();
        return string.Equals(actual, expectedSha256, StringComparison.OrdinalIgnoreCase);
    }

    private static (int Width, int Height) ReadPngDimensions(string path)
    {
        Span<byte> header = stackalloc byte[24];
        using var stream = File.OpenRead(path);
        if (stream.Read(header) != header.Length || !header[..8].SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
        {
            throw new InvalidDataException($"Not a valid PNG: {path}");
        }

        var width = (int)System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(header[16..20]);
        var height = (int)System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(header[20..24]);
        return (width, height);
    }

    private static string FindNativeRuntime()
    {
        var filename = OperatingSystem.IsWindows()
            ? "onnxruntime.dll"
            : OperatingSystem.IsMacOS() ? "libonnxruntime.dylib" : "libonnxruntime.so";
        var runtimeId = RuntimeInformation.RuntimeIdentifier;
        var ridSpecificPath = Path.Combine(AppContext.BaseDirectory, "runtimes", runtimeId, "native", filename);
        var match = File.Exists(ridSpecificPath)
            ? ridSpecificPath
            : Directory.GetFiles(AppContext.BaseDirectory, filename, SearchOption.AllDirectories)
                .OrderBy(path => path.Length)
                .FirstOrDefault();
        if (match is null)
        {
            throw new FileNotFoundException($"Could not find the native ONNX Runtime library {filename} for {runtimeId}.");
        }

        return $"{Path.GetFileName(match)} ({runtimeId}, {new FileInfo(match).Length:N0} bytes)";
    }

    private static string BuildReport(string corpusDirectory, MacBaseline baseline, int imageCount, long corpusBytes,
        IReadOnlyCollection<LanguageReport> groups, double classifierAgreement,
        int largeImageCount, double macLargeImageP95, double largeImageP95, FixtureReport fixtureReport,
        IReadOnlyCollection<ModelSize> models, string detectorPath, string classifierPath, string nativeRuntime)
    {
        var report = new StringBuilder();
        report.AppendLine("# OCR spike results");
        report.AppendLine();
        report.AppendLine($"- Runtime: .NET 10, RapidOcrNet 4.2.0, Microsoft.ML.OnnxRuntime 1.31.0 ({RuntimeInformation.RuntimeIdentifier})");
        report.AppendLine($"- Mac baseline: Vision `{baseline.RecognitionLevel}` revision {baseline.RecognitionRevision} on {baseline.OperatingSystem} ({baseline.Architecture})");
        report.AppendLine($"- Corpus: {imageCount} images, {corpusBytes:N0} PNG bytes; language coverage uses the language tags in the manifest");
        report.AppendLine("- CER: micro-average Levenshtein distance over NFC-normalized Unicode scalar values; whitespace collapsed before scoring");
        report.AppendLine("- RapidOcrNet timing: OCR plus classifier; one warm-up pass per recognizer language group, then one measured pass");
        report.AppendLine("- Arabic recognizer output is reversed into logical Unicode text order per detected line before reading-order joining and CER scoring");
        report.AppendLine("- Recognition assets were downloaded from the pinned ModelScope revision and SHA-256/byte-count checked before loading");
        report.AppendLine();
        report.AppendLine("## Language results");
        report.AppendLine();
        report.AppendLine("| Vision language | Model id | Mac CER | Windows CER¹ | Delta (points) | Mac p95 ms | Windows p95 ms |");
        report.AppendLine("|---|---|---:|---:|---:|---:|---:|");
        foreach (var group in groups)
        {
            report.AppendLine($"| {group.Language} | `{group.ModelId}` | {group.MacCer:P2} | {group.RapidCer:P2} | {group.DeltaPoints:+0.00;-0.00;0.00} | {group.MacP95Ms:F1} | {group.RapidP95Ms:F1} |");
        }

        report.AppendLine();
        report.AppendLine("¹ RapidOcrNet recognizer CER measured on this Mac as the Windows engine proxy.");
        report.AppendLine($"Classifier agreement: **{classifierAgreement:P1}** (gate ≥ 95%).");
        report.AppendLine($"1920×1080 images: **{largeImageCount}**; Mac Vision p95 OCR+classify: **{FormatOptional(macLargeImageP95)} ms**; RapidOcrNet p95 OCR+classify: **{FormatOptional(largeImageP95)} ms** (runner gate ≤ 1,500 ms).");
        var failedCerGroups = groups.Where(group => group.DeltaPoints > MaximumCerDeltaPoints).ToArray();
        report.AppendLine($"CER gate: **{(failedCerGroups.Length == 0 ? "PASS" : "FAIL")}** (RapidOcrNet ≤ Mac + {MaximumCerDeltaPoints:F1} points per language group).");
        if (failedCerGroups.Length > 0)
        {
            report.AppendLine($"Failing groups: {string.Join(", ", failedCerGroups.Select(group => $"{group.Language} (+{group.DeltaPoints:F2} points)"))}.");
        }
        report.AppendLine();
        report.AppendLine("## Fixture assertions");
        report.AppendLine();
        report.AppendLine($"- Paragraph: {(fixtureReport.ParagraphPassed ? "PASS" : "FAIL")} (capture before mountain, with a blank-line break)");
        report.AppendLine($"- Code: {(fixtureReport.CodePassed ? "PASS" : "FAIL")} (`CaptureRecord` and `collectRecords`)");
        report.AppendLine();
        report.AppendLine("## Model research and size");
        report.AppendLine();
        report.AppendLine("All 33 Vision languages in this corpus map to one of the recognizers below. The Chinese model is the PP-OCRv5 default multilingual recognizer for Simplified/Traditional Chinese, English, Japanese and the two Yue corpus groups. Russian and Ukrainian use the East-Slavic recognizer. The RapidAI model list records PP-OCRv5 ONNX URLs and hashes at revision `v3.10.0`; PaddleOCR and RapidOCR publish Apache-2.0 licensing for these source and converted model assets.");
        report.AppendLine();
        report.AppendLine("Sources: [RapidAI PP-OCRv5 model list, URLs and hashes](https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/default_models.yaml), [RapidAI model licensing and PaddleOCR attribution](https://github.com/RapidAI/RapidOCR/blob/main/README.md), [PaddleOCR license](https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE), [PP-OCRv5 language support](https://github.com/RapidAI/RapidOCRDocs/blob/main/docs/model_list.md).");
        report.AppendLine();
        report.AppendLine("| Model id | ONNX bytes | Dictionary bytes | License | Revision | ONNX source URL |");
        report.AppendLine("|---|---:|---:|---|---|---|");
        foreach (var model in models)
        {
            report.AppendLine($"| `{model.Id}` | {model.ModelBytes:N0} | {model.DictionaryBytes:N0} | {model.License} | `{model.Revision}` | [ModelScope]({model.Url}) |");
        }

        report.AppendLine();
        report.AppendLine("Common detector and orientation classifier from RapidOcrNet NuGet:");
        report.AppendLine();
        report.AppendLine($"- `{Path.GetFileName(detectorPath)}`: {new FileInfo(detectorPath).Length:N0} bytes");
        report.AppendLine($"- `{Path.GetFileName(classifierPath)}`: {new FileInfo(classifierPath).Length:N0} bytes");
        report.AppendLine($"- Native ORT: {nativeRuntime}");
        report.AppendLine();
        report.AppendLine("## Corpus files");
        report.AppendLine();
        report.AppendLine($"Images were read from `{corpusDirectory}`. Language groups and exact text are from `manifest.json`; the Mac values are from the paired baseline JSON.");
        return report.ToString();
    }

    private static string FormatOptional(double value) => double.IsFinite(value) ? value.ToString("F1", CultureInfo.InvariantCulture) : "n/a";

    private sealed record ManifestItem(
        [property: JsonPropertyName("file")] string File,
        [property: JsonPropertyName("category")] string Category,
        [property: JsonPropertyName("language")] string Language,
        [property: JsonPropertyName("scale")] double Scale,
        [property: JsonPropertyName("dark")] bool Dark,
        [property: JsonPropertyName("groundTruth")] string GroundTruth);

    private sealed record MacBaseline(
        [property: JsonPropertyName("schemaVersion")] int SchemaVersion,
        [property: JsonPropertyName("operatingSystem")] string OperatingSystem,
        [property: JsonPropertyName("architecture")] string Architecture,
        [property: JsonPropertyName("recognitionLevel")] string RecognitionLevel,
        [property: JsonPropertyName("recognitionRevision")] int RecognitionRevision,
        [property: JsonPropertyName("supportedRecognitionLanguages")] string[] SupportedRecognitionLanguages,
        [property: JsonPropertyName("images")] MacImage[] Images);

    private sealed record MacImage(
        [property: JsonPropertyName("file")] string File,
        [property: JsonPropertyName("text")] string Text,
        [property: JsonPropertyName("latencyMs")] double LatencyMs,
        [property: JsonPropertyName("classifierDecision")] string ClassifierDecision);

    private sealed record OcrLine(string Text, double MinX, double MinY, double MaxX, double MaxY, double Confidence)
    {
        public double MidY => (MinY + MaxY) / 2.0;
        public double Height => MaxY - MinY;
    }

    private sealed record Classification(string Decision, double Coverage, double MeanConfidence, int LineCount);
    private sealed record RecognizedImage(string Text, Classification Classification);
    private sealed record ImageMeasurement(ManifestItem Manifest, MacImage Mac, string ModelId, string RapidText,
        Classification Classification, int Width, int Height, double LatencyMs);
    private sealed record FixtureReport(bool ParagraphPassed, bool CodePassed, string ParagraphText, string CodeText)
    {
        public bool AllPassed => ParagraphPassed && CodePassed;
    }

    private sealed record LanguageReport(string Language, string ModelId, int Count, double MacCer, double RapidCer,
        double DeltaPoints, double MacP50Ms, double MacP95Ms, double RapidP50Ms, double RapidP95Ms,
        double MacLargeImageP95Ms, double RapidLargeImageP95Ms, int LargeImageCount, double ClassifierAgreement);

    private sealed record ModelSpec(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("scripts")] string[] Scripts,
        [property: JsonPropertyName("languages")] string[] Languages,
        [property: JsonPropertyName("url")] string Url,
        [property: JsonPropertyName("revision")] string Revision,
        [property: JsonPropertyName("sha256")] string Sha256,
        [property: JsonPropertyName("bytes")] long Bytes,
        [property: JsonPropertyName("dictUrl")] string DictUrl,
        [property: JsonPropertyName("dictSha256")] string DictSha256,
        [property: JsonPropertyName("license")] string License);

    private sealed record DownloadedModel(string ModelPath, string DictionaryPath);
    private sealed record ModelSize(string Id, string Revision, string Url, string License, long ModelBytes,
        long DictionaryBytes, string ModelPath, string DictionaryPath);
}
