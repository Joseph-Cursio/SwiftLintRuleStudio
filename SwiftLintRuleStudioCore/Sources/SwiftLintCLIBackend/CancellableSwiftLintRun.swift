//
//  CancellableSwiftLintRun.swift
//  SwiftLintRuleStudio
//
//  One `swiftlint` process that a cancelled caller terminates.
//

import Foundation
import LintStudioCore
import SwiftLintCLISeam

/// Runs one `swiftlint` process and terminates it when the calling task is cancelled.
///
/// `CLIToolActor.run` sees a process through to its exit (or its timeout), so an audit
/// cancelled mid-rule would leave a whole-workspace lint running for minutes. A simulation lint
/// runs here instead; everything else still goes through `CLIToolActor`.
nonisolated enum CancellableSwiftLintRun {
    /// The process's output, or `CancellationError` once a cancelled caller's process has
    /// exited. Applies SwiftLint's exit-code policy as `CLIToolActor` does: 0 and 2 succeed.
    static func run(
        binary: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: UInt64
    ) async throws -> Data {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = CLIToolActor.buildEnvironment(base: ProcessInfo.processInfo.environment)
        // A GUI app has no `PWD` of its own, or not the folder it lints in; SwiftLint fills
        // `${PWD}` in a config from it, as a shell run in that folder would.
        environment["PWD"] = workingDirectory.path
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let handle = ProcessHandle(process)
        let exit = ExitStatus()
        process.terminationHandler = { exit.settle($0.terminationStatus) }

        do {
            try process.run()
        } catch {
            throw SwiftLintError.executionFailed(message: "Failed to launch swiftlint: \(error.localizedDescription)")
        }

        let (stdout, stderr, status, timedOut) = await withTaskCancellationHandler {
            // The process closes its pipes when it exits or is terminated, which ends the reads.
            let timeout = Task {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                handle.terminate()
            }
            async let stdout = output.fileHandleForReading.readDataToEndOfFile()
            async let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            let streams = await (stdout, stderr)
            let status = await exit.value
            timeout.cancel()
            let timedOut = await timeout.result.isSuccess
            return (streams.0, streams.1, status, timedOut)
        } onCancel: {
            handle.terminate()
        }

        if Task.isCancelled { throw CancellationError() }
        if timedOut {
            throw SwiftLintError.executionFailed(
                message: "SwiftLint command timed out after \(timeoutSeconds) seconds."
            )
        }
        guard [0, 2].contains(status) else {
            if status == 127 { throw SwiftLintError.notFound }
            let message = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SwiftLintError.executionFailed(
                message: message.isEmpty ? "exit code \(status)" : "swiftlint failed: \(message)"
            )
        }
        return stdout
    }

    /// `Process` isn't `Sendable`; terminating it is safe from any thread.
    private final class ProcessHandle: @unchecked Sendable {
        private let process: Process

        init(_ process: Process) {
            self.process = process
        }

        /// SIGTERM, then SIGKILL if the process is still running a moment later — as
        /// `CLIToolActor` does. A wrapper that traps or ignores SIGTERM would otherwise keep a
        /// cancelled audit, and the mirror it is reading, waiting indefinitely.
        func terminate() {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            Task.detached { [self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    /// The process's exit status, awaited from its termination handler rather than the
    /// blocking `waitUntilExit()`, which can wedge a cooperative thread.
    private final class ExitStatus: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        private var waiter: CheckedContinuation<Int32, Never>?

        func settle(_ status: Int32) {
            lock.lock()
            if let waiter {
                self.waiter = nil
                lock.unlock()
                waiter.resume(returning: status)
            } else {
                self.status = status
                lock.unlock()
            }
        }

        var value: Int32 {
            get async {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if let status {
                        lock.unlock()
                        continuation.resume(returning: status)
                    } else {
                        waiter = continuation
                        lock.unlock()
                    }
                }
            }
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}
