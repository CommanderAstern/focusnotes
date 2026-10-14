import Foundation

/// Bounds the entire operation, including waiting to enter another actor. The
/// losing task is cancelled without awaiting non-cancellable helper I/O.
public enum SemanticDeadline {
    public static func run<Value: Sendable>(timeout: Duration, fallback: Value,
                                            operation: @escaping @Sendable () async -> Value) async -> Value {
        let race = DeadlineRace(fallback: fallback)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)
                let deadline = ContinuousClock.now.advanced(by: timeout)
                let timer = Task.detached(priority: .userInitiated) {
                    do { try await ContinuousClock().sleep(until: deadline) }
                    catch { return }
                    race.finish(fallback)
                }
                race.track(timer)
                let work = Task.detached(priority: .userInitiated) {
                    guard !Task.isCancelled, !race.isFinished else { return }
                    race.finish(await operation())
                }
                race.track(work)
            }
        } onCancel: { race.finish(fallback) }
    }
}

private final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let fallback: Value
    private var continuation: CheckedContinuation<Value, Never>?
    private var finished = false
    private var tasks: [Task<Void, Never>] = []

    init(fallback: Value) { self.fallback = fallback }
    var isFinished: Bool { lock.withLock { finished } }

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let ended = lock.withLock {
            if finished { return true }
            self.continuation = continuation
            return false
        }
        if ended { continuation.resume(returning: fallback) }
    }

    func track(_ task: Task<Void, Never>) {
        let ended = lock.withLock {
            if finished { return true }
            tasks.append(task)
            return false
        }
        if ended { task.cancel() }
    }

    func finish(_ value: Value) {
        let state = lock.withLock { () -> (CheckedContinuation<Value, Never>?, [Task<Void, Never>]) in
            guard !finished else { return (nil, []) }
            finished = true
            let state = (continuation, tasks)
            continuation = nil; tasks = []
            return state
        }
        state.1.forEach { $0.cancel() }
        state.0?.resume(returning: value)
    }
}
