import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct OCRLine: Equatable, Sendable {
    public let text: String
    /// Vision coordinates: normalized to 0...1, origin at the bottom left.
    public let boundingBox: CGRect
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

public struct OCRResult: Equatable, Sendable {
    public let text: String
    public let lines: [OCRLine]
    public let imageSize: CGSize

    public init(text: String, lines: [OCRLine], imageSize: CGSize) {
        self.text = text
        self.lines = lines
        self.imageSize = imageSize
    }
}

public enum OCRError: Error, Equatable, Sendable {
    case invalidImage
}

public enum OCR {
    public static func recognize(pngData: Data) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw OCRError.invalidImage }
            return try recognizeImage(image)
        }.value
    }

    public static func recognize(image: CGImage) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try recognizeImage(image)
        }.value
    }

    /// Vision language-model discovery and locale matching run once per process.
    private static let recognitionLanguages: [String] = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        var matches: [String] = []
        for preferred in Locale.preferredLanguages {
            let normalized = preferred.replacingOccurrences(of: "_", with: "-")
            let code = Locale(identifier: normalized).language.languageCode?.identifier
            let match = supported.first { $0.caseInsensitiveCompare(normalized) == .orderedSame }
                ?? supported.first { Locale(identifier: $0).language.languageCode?.identifier == code && code != nil }
            if let match, !matches.contains(match) { matches.append(match) }
        }
        return matches.isEmpty ? ["en-US"] : matches
    }()

    private static func recognizeImage(_ image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = recognitionLanguages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()
        let lines = readingOrder((request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
            return OCRLine(text: candidate.string, boundingBox: observation.boundingBox, confidence: candidate.confidence)
        })
        return OCRResult(text: joinedText(lines), lines: lines,
                         imageSize: CGSize(width: image.width, height: image.height))
    }

    private static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        let vertical = lines.sorted {
            if $0.boundingBox.midY != $1.boundingBox.midY { return $0.boundingBox.midY > $1.boundingBox.midY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        // Form rows first, then sort left to right. A fuzzy pairwise sort would not be transitive.
        var rows: [[OCRLine]] = []
        for line in vertical {
            if let anchor = rows.last?.first,
               abs(anchor.boundingBox.midY - line.boundingBox.midY)
                <= min(anchor.boundingBox.height, line.boundingBox.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { row in row.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    private static func joinedText(_ lines: [OCRLine]) -> String {
        let heights = lines.map(\.boundingBox.height).sorted()
        guard !heights.isEmpty else { return "" }
        let typicalHeight = heights[heights.count / 2]
        var text = ""
        for (index, line) in lines.enumerated() {
            if index > 0 {
                let previous = lines[index - 1]
                let verticalGap = previous.boundingBox.minY - line.boundingBox.maxY
                // One extra newline retains paragraph breaks without inventing blank lines per row.
                text += verticalGap > typicalHeight * 1.3 ? "\n\n" : "\n"
            }
            text += line.text
        }
        return text
    }
}
