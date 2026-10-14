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
        return digest(Data("\(url.path)\u{0}\(size.int64Value)\u{0}\(modified.timeIntervalSince1970.bitPattern)".utf8))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
