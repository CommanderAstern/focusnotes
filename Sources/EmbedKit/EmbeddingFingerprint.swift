import CryptoKit
import Foundation

public enum EmbeddingFingerprint {
    /// Hash the exact prompt plus title/body (or OCR) sent to the tokenizer.
    public static func document(_ text: String, title: String?) -> String {
        digest(Data(EmbeddingKind.document(title: title).input(text).utf8))
    }

    /// Metadata avoids reading all image bytes on every reconciliation. Include
    /// the resolved path so moving to a different asset also changes the input.
    public static func image(at url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            throw EmbeddingError.invalid("Missing image size or modification time")
        }
        return image(path: url.path, size: size.int64Value, modifiedAt: modified)
    }

    /// Fingerprints metadata read from a validated descriptor while preserving
    /// the path/size/mtime identity used by existing image vectors.
    public static func image(path: String, size: Int64, modifiedAt: Date) -> String {
        digest(Data("\(path)\u{0}\(size)\u{0}\(modifiedAt.timeIntervalSince1970.bitPattern)".utf8))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
