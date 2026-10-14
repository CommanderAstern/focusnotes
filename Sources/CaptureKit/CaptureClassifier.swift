import CoreGraphics

public enum CaptureDecision: String, Sendable {
    case text
    case image
}

public struct CaptureMetrics: Equatable, Sendable {
    public let textCoverage: Double
    public let meanConfidence: Float
    public let lineCount: Int
}

public struct CaptureClassification: Equatable, Sendable {
    public let decision: CaptureDecision
    public let metrics: CaptureMetrics
}

public enum CaptureClassifier {
    // At 2x the paragraph/code fixtures cover ~22–23%; the grid/diagram cover ~1–6%.
    // Use a margin between those groups rather than requiring near-full page coverage.
    public static let minimumTextCoverage = 0.12
    public static let minimumMeanConfidence: Float = 0.75
    public static let minimumLineCount = 4
    /// Tight crops of one to three lines (a sentence, a heading) are dense enough to be text.
    public static let denseCropCoverage = 0.25

    public static func classify(_ result: OCRResult) -> CaptureClassification {
        classify(lines: result.lines, imageSize: result.imageSize)
    }

    /// Sparse labels and short table cells stay images; dense, confident lines become text.
    /// This intentionally uses only OCR geometry, so dense tables can still look like prose.
    public static func classify(lines: [OCRLine], imageSize: CGSize) -> CaptureClassification {
        let imageArea = imageSize.width * imageSize.height
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let textArea = usable.reduce(0.0) { total, line in
            let box = line.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !box.isNull else { return total }
            return total + box.width * imageSize.width * box.height * imageSize.height
        }
        let coverage = imageArea.isFinite && imageArea > 0 ? Double(textArea / imageArea) : 0
        let confidence = usable.isEmpty ? 0 : usable.reduce(Float(0)) { $0 + $1.confidence } / Float(usable.count)
        let metrics = CaptureMetrics(textCoverage: coverage, meanConfidence: confidence, lineCount: usable.count)
        let isProse = coverage >= minimumTextCoverage && usable.count >= minimumLineCount
        let isDenseCrop = coverage >= denseCropCoverage && !usable.isEmpty
        let decision: CaptureDecision = confidence >= minimumMeanConfidence && (isProse || isDenseCrop) ? .text : .image
        return CaptureClassification(decision: decision, metrics: metrics)
    }
}
