import Foundation

/// Implements the pinned Gemma tokenizer's literal-space normalizer, Split
/// pre-tokenizer, ranked BPE, byte fallback, added tokens and BOS/EOS template.
/// Immutable after initialization; safe to share between actors.
public final class Tokenizer: Sendable {
    private struct Merge: Sendable { let rank: Int; let id: Int64 }
    // Swift String equality is canonically equivalent; BPE vocabulary equality
    // is byte-exact (e.g. composed/decomposed accents are distinct entries).
    private let vocabulary: [Data: Int64]
    private let merges: [UInt64: Merge]
    private let special: [(text: String, id: Int64)]
    private let bytes: [Int64]

    public init(tokenizerJSON: URL) throws {
        let json = try Data(contentsOf: tokenizerJSON)
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let model = root["model"] as? [String: Any], model["type"] as? String == "BPE",
              model["byte_fallback"] as? Bool == true, model["ignore_merges"] as? Bool == false,
              model["dropout"] is NSNull, model["continuing_subword_prefix"] is NSNull,
              model["end_of_word_suffix"] is NSNull,
              let normalizer = root["normalizer"] as? [String: Any],
              normalizer["type"] as? String == "Replace", normalizer["content"] as? String == "▁",
              (normalizer["pattern"] as? [String: String])?["String"] == " ",
              let pre = root["pre_tokenizer"] as? [String: Any], pre["type"] as? String == "Split",
              (pre["pattern"] as? [String: String])?["String"] == " ",
              pre["behavior"] as? String == "MergedWithPrevious", pre["invert"] as? Bool == false,
              let post = root["post_processor"] as? [String: Any], post["type"] as? String == "TemplateProcessing",
              let template = post["single"] as? [[String: Any]], template.count == 3,
              (template[0]["SpecialToken"] as? [String: Any])?["id"] as? String == "<bos>",
              (template[2]["SpecialToken"] as? [String: Any])?["id"] as? String == "<eos>",
              let added = root["added_tokens"] as? [[String: Any]] else {
            throw EmbeddingError.invalid("Unsupported tokenizer configuration; expected pinned Gemma BPE")
        }
        // Foundation's dictionary decoders also canonicalize JSON keys. Read
        // this one object from UTF-8 directly, preserving all 262,144 entries.
        var reader = ExactJSONReader(bytes: Array(json))
        try reader.field("model")
        try reader.field("vocab")
        let vocab = try reader.vocabulary()
        var mergeReader = ExactJSONReader(bytes: reader.bytes)
        try mergeReader.field("model")
        try mergeReader.field("merges")
        let pairs = try mergeReader.mergePairs()
        guard vocab[Data("<bos>".utf8)] == 2, vocab[Data("<eos>".utf8)] == 1 else {
            throw EmbeddingError.invalid("Invalid BOS/EOS vocabulary IDs")
        }
        var table: [UInt64: Merge] = [:]
        table.reserveCapacity(pairs.count)
        for (rank, pair) in pairs.enumerated() {
            guard let left = vocab[pair.0], let right = vocab[pair.1],
                  let id = vocab[pair.0 + pair.1] else { throw EmbeddingError.invalid("Invalid BPE merge at rank \(rank)") }
            table[Self.pair(left, right)] = Merge(rank: rank, id: id)
        }
        var specials: [(String, Int64)] = []
        for token in added {
            guard let text = token["content"] as? String, let id = token["id"] as? Int64,
                  token["single_word"] as? Bool == false, token["lstrip"] as? Bool == false,
                  token["rstrip"] as? Bool == false, token["normalized"] as? Bool == false else {
                throw EmbeddingError.invalid("Unsupported added token")
            }
            specials.append((text, id))
        }
        self.vocabulary = vocab
        self.merges = table
        self.special = specials.sorted { $0.0.utf8.count > $1.0.utf8.count }
        self.bytes = try (0..<256).map { byte in
            guard let id = vocab[Data(String(format: "<0x%02X>", byte).utf8)] else {
                throw EmbeddingError.invalid("Missing byte fallback token")
            }
            return id
        }
    }

    /// maxLength includes BOS/EOS; truncation always retains both template tokens.
    public func encode(_ text: String, maxLength: Int = 2048) throws -> [Int64] {
        guard maxLength >= 2 else { throw EmbeddingError.invalid("maxLength must be at least two") }
        var ids: [Int64] = [2]
        var remaining = text[...]
        while !remaining.isEmpty {
            var earliest: Range<String.Index>?
            var found: Int64 = 0
            for token in special {
                if let range = remaining.range(of: token.text), earliest == nil || range.lowerBound < earliest!.lowerBound {
                    earliest = range
                    found = token.id
                }
            }
            if let range = earliest {
                ids += bpe(String(remaining[..<range.lowerBound]))
                ids.append(found)
                remaining = remaining[range.upperBound...]
            } else {
                ids += bpe(String(remaining))
                break
            }
            if ids.count >= maxLength - 1 { break }
        }
        return Array(ids.prefix(maxLength - 1)) + [1]
    }

    private static func pair(_ a: Int64, _ b: Int64) -> UInt64 { UInt64(a) << 32 | UInt64(b) }

    private struct Candidate {
        let rank: Int
        let index: Int
        let right: Int
        let generation: Int
        let rightGeneration: Int
        let id: Int64
        func before(_ other: Candidate) -> Bool {
            rank < other.rank || (rank == other.rank && index < other.index)
        }
    }

    private func bpe(_ text: String) -> [Int64] {
        // Normalization removes every literal space, so Split(" ") is a no-op.
        var ids: [Int64] = []
        for scalar in text.unicodeScalars {
            let s = scalar.value == 32 ? "▁" : String(scalar)
            if let id = vocabulary[Data(s.utf8)] { ids.append(id) }
            else { ids += s.utf8.map { bytes[Int($0)] } }
        }
        guard ids.count > 1 else { return ids }
        var next = Array(1...ids.count)
        var previous = Array(-1..<(ids.count - 1))
        var generations = [Int](repeating: 0, count: ids.count)
        var heap: [Candidate] = []
        func push(_ candidate: Candidate) {
            heap.append(candidate)
            var i = heap.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if !heap[i].before(heap[p]) { break }
                heap.swapAt(i, p); i = p
            }
        }
        func offer(_ i: Int) {
            guard i >= 0, next[i] < ids.count, ids[i] >= 0,
                  let merge = merges[Self.pair(ids[i], ids[next[i]])] else { return }
            push(Candidate(rank: merge.rank, index: i, right: next[i], generation: generations[i],
                           rightGeneration: generations[next[i]], id: merge.id))
        }
        func pop() -> Candidate? {
            guard !heap.isEmpty else { return nil }
            let first = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while 2 * i + 1 < heap.count {
                    var child = 2 * i + 1
                    if child + 1 < heap.count && heap[child + 1].before(heap[child]) { child += 1 }
                    if !heap[child].before(heap[i]) { break }
                    heap.swapAt(child, i); i = child
                }
            }
            return first
        }
        for i in 0..<(ids.count - 1) { offer(i) }
        while let candidate = pop() {
            let i = candidate.index, j = candidate.right
            guard ids[i] >= 0, ids[j] >= 0, next[i] == j,
                  generations[i] == candidate.generation, generations[j] == candidate.rightGeneration else { continue }
            ids[i] = candidate.id; ids[j] = -1
            generations[i] += 1; generations[j] += 1
            next[i] = next[j]
            if next[j] < ids.count { previous[next[j]] = i }
            offer(previous[i]); offer(i)
        }
        return ids.filter { $0 >= 0 }
    }
}

private struct ExactJSONReader {
    let bytes: [UInt8]
    var index = 0
    mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func expect(_ byte: UInt8) throws {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { throw EmbeddingError.invalid("Invalid tokenizer JSON") }
        index += 1
    }
    mutating func field(_ name: String) throws {
        try expect(123)
        while true {
            whitespace()
            if index >= bytes.count || bytes[index] == 125 { throw EmbeddingError.invalid("Missing JSON field \(name)") }
            let key = try string()
            try expect(58)
            if key == Data(name.utf8) { return }
            try skip()
            whitespace()
            if index < bytes.count && bytes[index] == 44 { index += 1 }
            else { throw EmbeddingError.invalid("Missing JSON field \(name)") }
        }
    }
    mutating func mergePairs() throws -> [(Data, Data)] {
        try expect(91)
        var pairs: [(Data, Data)] = []
        pairs.reserveCapacity(515_000)
        while true {
            whitespace()
            if index < bytes.count && bytes[index] == 93 { index += 1; return pairs }
            try expect(91)
            let left = try string()
            try expect(44)
            let right = try string()
            try expect(93)
            pairs.append((left, right))
            whitespace()
            if index < bytes.count && bytes[index] == 44 { index += 1 }
            else if index >= bytes.count || bytes[index] != 93 { throw EmbeddingError.invalid("Invalid merges delimiter") }
        }
    }
    mutating func vocabulary() throws -> [Data: Int64] {
        try expect(123)
        var result: [Data: Int64] = [:]
        result.reserveCapacity(262_144)
        while true {
            whitespace()
            if index < bytes.count && bytes[index] == 125 { index += 1; return result }
            let key = try string()
            try expect(58)
            whitespace()
            let start = index
            while index < bytes.count && bytes[index] >= 48 && bytes[index] <= 57 { index += 1 }
            guard let id = Int64(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw EmbeddingError.invalid("Invalid vocabulary token ID")
            }
            result[key] = id
            whitespace()
            guard index < bytes.count else { throw EmbeddingError.invalid("Incomplete vocabulary") }
            if bytes[index] == 44 { index += 1 }
            else if bytes[index] != 125 { throw EmbeddingError.invalid("Invalid vocabulary delimiter") }
        }
    }
    mutating func string() throws -> Data {
        try expect(34)
        var output = Data()
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 { return output }
            if byte != 92 { output.append(byte); continue }
            guard index < bytes.count else { break }
            let escape = bytes[index]; index += 1
            switch escape {
            case 34, 47, 92: output.append(escape)
            case 98: output.append(8)
            case 102: output.append(12)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 117:
                var code = try hex()
                if (0xD800...0xDBFF).contains(code) {
                    guard index + 1 < bytes.count, bytes[index] == 92, bytes[index + 1] == 117 else {
                        throw EmbeddingError.invalid("Invalid JSON surrogate pair")
                    }
                    index += 2
                    let low = try hex()
                    guard (0xDC00...0xDFFF).contains(low) else { throw EmbeddingError.invalid("Invalid JSON surrogate") }
                    code = 0x10000 + ((code - 0xD800) << 10) + low - 0xDC00
                }
                guard let scalar = UnicodeScalar(code) else { throw EmbeddingError.invalid("Invalid JSON Unicode") }
                output.append(contentsOf: String(scalar).utf8)
            default: throw EmbeddingError.invalid("Invalid JSON escape")
            }
        }
        throw EmbeddingError.invalid("Unterminated JSON string")
    }
    mutating func hex() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw EmbeddingError.invalid("Incomplete JSON escape") }
        guard let value = UInt32(String(decoding: bytes[index..<(index + 4)], as: UTF8.self), radix: 16) else {
            throw EmbeddingError.invalid("Invalid JSON hex escape")
        }
        index += 4
        return value
    }
    mutating func skip() throws {
        whitespace()
        guard index < bytes.count else { throw EmbeddingError.invalid("Incomplete JSON value") }
        if bytes[index] == 34 { _ = try string(); return }
        if bytes[index] == 123 || bytes[index] == 91 {
            let end: UInt8 = bytes[index] == 123 ? 125 : 93
            index += 1
            while true {
                whitespace()
                guard index < bytes.count else { throw EmbeddingError.invalid("Incomplete JSON container") }
                if bytes[index] == end { index += 1; return }
                if bytes[index] == 44 || bytes[index] == 58 { index += 1 }
                else { try skip() }
            }
        }
        while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
    }
}
