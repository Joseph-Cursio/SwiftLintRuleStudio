//
//  CancellableSwiftLintRunTests.swift
//  SwiftLintRuleStudioTests
//
//  A simulation lint's process ends when the audit waiting on it is cancelled.
//

import Foundation
@testable import SwiftLintCLIBackend
import SwiftLintCLISeam
import Testing

struct CancellableSwiftLintRunTests {
    @Test("Cancelling the caller terminates the process and throws CancellationError")
    func cancellationTerminatesTheProcess() async throws {
        let started = Date()
        let run = Task {
            try await CancellableSwiftLintRun.run(
                binary: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeoutSeconds: 60
            )
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        run.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await run.value
        }
        #expect(Date().timeIntervalSince(started) < 10, "the 30-second process was stopped")
    }

    @Test("A process that ignores SIGTERM is killed")
    func ignoredTerminationIsEscalated() async throws {
        // `exec` keeps the shell's pid, with TERM still ignored, so only SIGKILL ends it.
        let started = Date()
        let run = Task {
            try await CancellableSwiftLintRun.run(
                binary: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; exec sleep 30"],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeoutSeconds: 60
            )
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        run.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await run.value
        }
        #expect(Date().timeIntervalSince(started) < 10, "the process ignoring SIGTERM was killed")
    }

    @Test("A lint run through the shell, as when swiftlint is found only on its PATH, is cancellable too")
    func shellRunIsCancellable() async throws {
        let started = Date()
        let run = Task {
            try await CancellableSwiftLintRun.run(
                binary: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", "sleep 30"],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeoutSeconds: 60
            )
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        run.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await run.value
        }
        #expect(Date().timeIntervalSince(started) < 10, "the shell and its command were stopped")
    }

    @Test("The process runs with PWD naming its working directory, which SwiftLint fills ${PWD} from")
    func workingDirectoryIsInPWD() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PWDTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let output = try await CancellableSwiftLintRun.run(
            binary: URL(fileURLWithPath: "/usr/bin/printenv"),
            arguments: ["PWD"],
            workingDirectory: folder,
            timeoutSeconds: 60
        )

        #expect(String(data: output, encoding: .utf8) == folder.path + "\n")
    }

    @Test("A process that finishes returns its output")
    func finishedProcessReturnsOutput() async throws {
        let output = try await CancellableSwiftLintRun.run(
            binary: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["[]"],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 60
        )

        #expect(String(data: output, encoding: .utf8) == "[]\n")
    }

    @Test("An exit code SwiftLint treats as failure is an execution failure")
    func failingProcessThrows() async throws {
        await #expect(throws: SwiftLintError.self) {
            _ = try await CancellableSwiftLintRun.run(
                binary: URL(fileURLWithPath: "/usr/bin/false"),
                arguments: [],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeoutSeconds: 60
            )
        }
    }
}
