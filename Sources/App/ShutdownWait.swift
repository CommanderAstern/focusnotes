import Foundation

@MainActor
private final class ShutdownRace {
    var worker: Task<Void, Never>?
    var deadline: Task<Void, Never>?
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func finish(_ completed: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        worker?.cancel(); worker = nil
        deadline?.cancel(); deadline = nil
        continuation.resume(returning: completed)
    }
}

@MainActor
func waitForShutdown(_ task: Task<Void, Never>, until deadline: ContinuousClock.Instant) async -> Bool {
    await withCheckedContinuation { continuation in
        let race = ShutdownRace(continuation)
        race.worker = Task { await task.value; race.finish(true) }
        race.deadline = Task {
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            race.finish(false)
        }
    }
}
