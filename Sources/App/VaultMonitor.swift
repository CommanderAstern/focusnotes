import Core
import Foundation

/// Event-driven index and OCR work run on the utility actor task; no idle polling.
final class VaultMonitor: @unchecked Sendable {
    private let watcher: VaultWatcher
    private let refresh: VaultRefresh
    private let lock = NSLock()
    private var stopped = false

    init(vault: Vault, operation: @escaping @Sendable (Bool, Bool) async -> Void) {
        let refresh = VaultRefresh(operation: operation)
        self.refresh = refresh
        watcher = VaultWatcher(vault: vault) { [weak refresh] change in
            Task.detached(priority: .utility) { await refresh?.changed(change) }
        }
    }

    var isRunning: Bool { lock.withLock { !stopped && watcher.isRunning } }

    func start() {
        lock.withLock {
            guard !stopped else { return }
            watcher.start()
        }
    }

    /// Permanent for this pipeline, so a late launch sync cannot restart a terminating app.
    func stop() {
        lock.withLock {
            stopped = true
            watcher.stop()
        }
        Task.detached(priority: .utility) { [refresh] in await refresh.stop() }
    }

    func sync() async { await refresh.run(notes: true, assets: false) }
    func backfill() async { await refresh.run(notes: false, assets: true) }
}

private actor VaultRefresh {
    private let operation: @Sendable (Bool, Bool) async -> Void
    private var worker: Task<Void, Never>?
    private var notesDirty = false
    private var assetsDirty = false
    private var stopped = false

    init(operation: @escaping @Sendable (Bool, Bool) async -> Void) { self.operation = operation }

    func changed(_ change: VaultChange) {
        let notes = change.needsFullSync || !change.notesChanged.isEmpty
        // A new/edited note can introduce an image reference that also needs OCR.
        enqueue(notes: notes, assets: notes || !change.assetsChanged.isEmpty)
    }

    func run(notes: Bool, assets: Bool) async {
        enqueue(notes: notes, assets: assets)
        await worker?.value
    }

    private func enqueue(notes: Bool, assets: Bool) {
        guard !stopped else { return }
        notesDirty = notesDirty || notes
        assetsDirty = assetsDirty || assets
        guard worker == nil else { return }
        worker = Task.detached(priority: .utility) { [self] in await drain() }
    }

    private func drain() async {
        while !stopped, !Task.isCancelled, notesDirty || assetsDirty {
            let notes = notesDirty, assets = assetsDirty
            notesDirty = false; assetsDirty = false
            await operation(notes, assets)
            // Changes received during the await merge into one additional pass.
        }
        worker = nil
    }

    func stop() {
        stopped = true
        notesDirty = false; assetsDirty = false
        worker?.cancel()
    }
}
