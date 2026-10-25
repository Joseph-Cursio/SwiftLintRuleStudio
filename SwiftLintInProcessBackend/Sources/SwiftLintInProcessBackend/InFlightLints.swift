import Foundation

/// The rule-simulation lints still running, by the workspace path each reads.
///
/// SwiftLint can't be interrupted mid-lint. When the caller of one is cancelled — an audit
/// whose workspace closed — the backend stops waiting and the lint runs on unobserved, its
/// result discarded. Its mirror must outlive it: SwiftLint treats a config that vanishes
/// mid-read as fatal, which in-process is the app. So the caller asks to wait for the lints
/// still reading a path before removing what is there.
final class InFlightLints: @unchecked Sendable {
    private let lock = NSLock()
    private var lints: [String: [UUID: Task<Data, Error>]] = [:]

    /// Runs `lint` on the cooperative pool and returns what it returns — unless the caller is
    /// cancelled first, when it throws `CancellationError` at once and leaves `lint` running.
    func run(at workspacePath: URL, _ lint: @escaping @Sendable () throws -> Data) async throws -> Data {
        let key = workspacePath.path
        let id = UUID()
        let task = Task.detached(priority: .userInitiated) { try lint() }
        insert(task, id: id, at: key)
        Task.detached { [self] in
            _ = await task.result
            remove(id, at: key)
        }
        return try await Self.value(of: task)
    }

    /// Returns once no lint started at `workspacePath` is still running.
    func waitForLints(at workspacePath: URL) async {
        for task in running(at: workspacePath.path) {
            _ = await task.result
        }
    }

    private func insert(_ task: Task<Data, Error>, id: UUID, at key: String) {
        lock.withLock { lints[key, default: [:]][id] = task }
    }

    private func remove(_ id: UUID, at key: String) {
        lock.withLock {
            lints[key]?[id] = nil
            if lints[key]?.isEmpty == true { lints[key] = nil }
        }
    }

    private func running(at key: String) -> [Task<Data, Error>] {
        lock.withLock { Array((lints[key] ?? [:]).values) }
    }

    /// `task`'s value, or `CancellationError` as soon as the caller is cancelled.
    private static func value(of task: Task<Data, Error>) async throws -> Data {
        let outcome = Outcome()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                outcome.wait(with: continuation)
                Task.detached { outcome.settle(await task.result) }
            }
        } onCancel: {
            outcome.settle(.failure(CancellationError()))
        }
    }

    /// The first of the lint's result and the caller's cancellation, delivered once.
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?
        private var result: Result<Data, Error>?

        func wait(with continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func settle(_ result: Result<Data, Error>) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: result)
        }
    }
}
