import Core
import EmbedKit
import Foundation
import IOKit.ps
import os

struct SemanticHits: Sendable {
    var text: [SearchHit] = []
    var images: [SearchHit] = []
}

/// Coordinates disposable vectors. Models and runtime stay in EmbedHelper.
actor SemanticIndexer {
    private static let embeddingModelFiles = [
        "onnx/model_quantized.onnx", "onnx/model_quantized.onnx_data",
        "onnx/vision_encoder_q4.onnx", "onnx/vision_encoder_q4.onnx_data"
    ]

    nonisolated let modelsDirectory: URL
    private let index: SearchIndex
    private let vault: Vault
    private let databaseURL: URL
    private let helperExecutable: URL
    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "semantic")
    private var enabled: Bool
    private var store: VectorStore?
    private var client: EmbedClient?
    private var debounce: Task<Void, Never>?
    private var job: Task<Void, Never>?
    private var rerun = false

    init(index: SearchIndex, vault: Vault, stateDirectory: URL, modelsDirectory: URL) {
        self.index = index; self.vault = vault; self.modelsDirectory = modelsDirectory
        self.databaseURL = stateDirectory.appendingPathComponent("vectors.sqlite")
        // Bundle lookup in production; sibling product permits SwiftPM self-tests.
        self.helperExecutable = Bundle.main.url(forAuxiliaryExecutable: "EmbedHelper")
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("EmbedHelper")
        self.enabled = Self.modelsInstalled(in: modelsDirectory)
    }

    nonisolated static func modelsInstalled(in directory: URL) -> Bool {
        ["onnx/model_quantized.onnx", "onnx/model_quantized.onnx_data",
         "onnx/vision_encoder_q4.onnx", "onnx/vision_encoder_q4.onnx_data",
         "tokenizer.json", "processor_config.json", "libonnxruntime.dylib"].allSatisfy {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { schedule() }
        else { debounce?.cancel(); debounce = nil; job?.cancel(); rerun = false }
    }

    /// Cancels only the timer, never an inference already warming the helper.
    func schedule() {
        guard enabled else { return }
        debounce?.cancel()
        debounce = Task.detached(priority: .utility) { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.startJob()
        }
    }

    private func startJob() {
        debounce = nil
        guard enabled else { return }
        guard job == nil else { rerun = true; return }
        job = Task.detached(priority: .utility) { [self] in
            do { try await reconcile() }
            catch { logger.error("Embedding deferred: \(String(describing: error), privacy: .public)") }
            await finishedJob()
        }
    }

    private func finishedJob() {
        job = nil
        if rerun { rerun = false; startJob() }
    }

    /// Used by the permission-free self-test; production never waits for backfill.
    func flush() async {
        debounce?.cancel(); debounce = nil
        while let active = job { await active.value }
        startJob()
        while let active = job { await active.value }
    }

    private func resources() throws -> (EmbedClient, VectorStore) {
        if client == nil { client = try EmbedClient(helperExecutable: helperExecutable, modelsDirectory: modelsDirectory) }
        if store == nil {
            let modelFiles = Self.embeddingModelFiles.map { modelsDirectory.appendingPathComponent($0) }
            store = try VectorStore(url: databaseURL, modelFiles: modelFiles)
        }
        return (client!, store!)
    }

    private func activeResources() throws -> (EmbedClient, VectorStore)? {
        guard enabled, !Task.isCancelled else { return nil }
        return try resources()
    }

    private func isEnabled() -> Bool { enabled }

    // Snapshot/SQLite/file work runs on the detached job, outside this actor.
    // Only resource ownership and scheduling need the coordinator's isolation.
    nonisolated private func reconcile() async throws {
        guard await isEnabled() else { return }
        let blocks = try await index.embeddableBlocks()
        guard let (client, store) = try await activeResources() else { return }
        let existing = Set(try store.keys())
        let fingerprints = try store.fingerprints()
        var expected = Set(blocks.map(\.key))
        for block in blocks where block.kind == .image && !block.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expected.insert(block.key + "#ocr")
        }
        try store.remove(keys: Array(existing.subtracting(expected)))
        // Each request has one title, so batch within a note (at most 16).
        var batch: [(key: String, body: String, title: String, fingerprint: String)] = []
        for block in blocks {
            try Task.checkCancellation()
            guard await isEnabled() else { return }
            if block.kind == .image {
                guard Self.imagesAllowed else { continue }
                if !block.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   fingerprints[block.key + "#ocr"] != EmbeddingFingerprint.document(block.ocrText, title: block.noteTitle) {
                    if batch.first?.title != block.noteTitle || batch.count == 16 {
                        try await embedBatch(batch, client: client, store: store); batch.removeAll()
                    }
                    batch.append((block.key + "#ocr", block.ocrText, block.noteTitle,
                                  EmbeddingFingerprint.document(block.ocrText, title: block.noteTitle)))
                }
            } else if fingerprints[block.key] != EmbeddingFingerprint.document(block.body, title: block.noteTitle) {
                if batch.first?.title != block.noteTitle || batch.count == 16 {
                    try await embedBatch(batch, client: client, store: store); batch.removeAll()
                }
                batch.append((block.key, block.body, block.noteTitle,
                              EmbeddingFingerprint.document(block.body, title: block.noteTitle)))
            }
        }
        try await embedBatch(batch, client: client, store: store)
        for block in blocks where block.kind == .image {
            try Task.checkCancellation()
            guard await isEnabled(), Self.imagesAllowed else { return }
            do {
                guard let path = block.assetPath else { continue }
                let url = vault.root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
                guard !path.hasPrefix("/"), url.path.hasPrefix(vault.root.path + "/") else { continue }
                let fingerprint = try EmbeddingFingerprint.image(at: url)
                guard fingerprints[block.key] != fingerprint else { continue }
                let png = try Data(contentsOf: url)
                let vector = try await client.embedImage(png)
                try Task.checkCancellation()
                try store.upsert(key: block.key, vector: vector, fingerprint: fingerprint)
            } catch is CancellationError { throw CancellationError() }
            catch { logger.error("Image embedding deferred for \(block.key, privacy: .public): \(String(describing: error), privacy: .public)") }
        }
    }

    nonisolated private func embedBatch(_ batch: [(key: String, body: String, title: String, fingerprint: String)], client: EmbedClient, store: VectorStore) async throws {
        guard !batch.isEmpty else { return }
        try Task.checkCancellation()
        let vectors = try await client.embedDocuments(batch.map(\.body), title: batch[0].title)
        try Task.checkCancellation()
        for (block, vector) in zip(batch, vectors) {
            try store.upsert(key: block.key, vector: vector, fingerprint: block.fingerprint)
        }
    }

    nonisolated static var imagesAllowed: Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        guard (thermal == .nominal || thermal == .fair), !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return source as String == kIOPSACPowerValue
    }

    func warm() async {
        guard enabled else { return }
        do { _ = try await resources().0.ping() }
        catch { logger.error("Helper warmup failed: \(String(describing: error), privacy: .public)") }
    }

    nonisolated func search(_ query: String, timeout: Duration = .milliseconds(350)) async -> SemanticHits {
        await SemanticDeadline.run(timeout: timeout, fallback: SemanticHits()) { [self] in
            await searchWork(query)
        }
    }

    nonisolated private func searchWork(_ query: String) async -> SemanticHits {
        do {
            guard let (client, store) = try await activeResources() else { return SemanticHits() }
            try Task.checkCancellation()
            let vector = try await client.embedLatestQuery(query)
            try Task.checkCancellation()
            let nearest = try store.nearest(to: vector, limit: 40)
            try Task.checkCancellation()
            var scores: [String: Float] = [:]
            for (key, score) in nearest {
                let block = key.hasSuffix("#ocr") ? String(key.dropLast(4)) : key
                scores[block] = max(scores[block] ?? -.infinity, score)
            }
            let ranked = scores.keys.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0]! > scores[$1]! }
            let hits = try await index.hits(forEmbeddingKeys: ranked)
            try Task.checkCancellation()
            var result = SemanticHits()
            for key in ranked {
                guard let hit = hits[key] else { continue }
                if hit.blockKind == .image { result.images.append(hit) }
                else { result.text.append(hit) }
            }
            return result
        } catch is CancellationError {
            return SemanticHits()
        } catch {
            logger.error("Semantic query skipped: \(String(describing: error), privacy: .public)")
            return SemanticHits()
        }
    }

    nonisolated static func fuse(keyword: [SearchHit], semantic: SemanticHits, limit: Int = 40) -> [SearchHit] {
        var scores: [String: Double] = [:]
        var hits: [String: SearchHit] = [:]
        var order: [String: Int] = [:]
        for list in [keyword, semantic.text, semantic.images] {
            var seen: Set<String> = []
            for (rank, hit) in list.enumerated() where seen.insert(hit.embeddingKey).inserted {
                let key = hit.embeddingKey
                scores[key, default: 0] += 1 / Double(60 + rank + 1)
                if hits[key] == nil { hits[key] = hit; order[key] = order.count }
            }
        }
        return scores.keys.sorted {
            scores[$0] == scores[$1] ? order[$0]! < order[$1]! : scores[$0]! > scores[$1]!
        }.prefix(max(0, limit)).compactMap { hits[$0] }
    }
}
