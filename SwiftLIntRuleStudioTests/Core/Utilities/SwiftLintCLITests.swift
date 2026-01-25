//
//  SwiftLintCLITests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLITests {
    
    actor CommandRecorder {
        private(set) var calls: [(String, [String])] = []
        
        func record(_ command: String, _ arguments: [String]) {
            calls.append((command, arguments))
        }
    }
    
    @Test("SwiftLintError has correct error descriptions")
    func testSwiftLintErrorDescriptions() {
        let notFoundError = SwiftLintError.notFound
        #expect(notFoundError.errorDescription?.contains("not found") == true)
        
        let invalidVersionError = SwiftLintError.invalidVersion
        #expect(invalidVersionError.errorDescription?.contains("version") == true)
        
        let executionError = SwiftLintError.executionFailed(message: "Test error")
        #expect(executionError.errorDescription?.contains("Test error") == true)
    }
    
    // Note: Actual CLI execution tests would require SwiftLint to be installed
    // These would be integration tests rather than unit tests
    // For now, we test the error types and structure

    @Test("SwiftLintCLI getVersion uses command runner output")
    func testGetVersionUsesRunner() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data("1.2.3\n".utf8), Data())
        }
        
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let version = try await cli.getVersion()
        #expect(version == "1.2.3")
    }

    @Test("SwiftLintCLI getVersion throws on invalid output")
    func testGetVersionInvalidOutput() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data([0xFF, 0xFE]), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.getVersion()
            #expect(false, "Expected invalidVersion error")
        } catch let error as SwiftLintError {
            switch error {
            case .invalidVersion:
                #expect(true)
            default:
                #expect(false, "Expected invalidVersion error")
            }
        } catch {
            #expect(false, "Expected SwiftLintError")
        }
    }
    
    @Test("SwiftLintCLI executeLintCommand builds arguments")
    func testExecuteLintCommandArguments() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data())
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        try Data("rules: {}".utf8).write(to: configURL)
        
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeLintCommand(configPath: configURL, workspacePath: tempDir)
        
        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "swiftlint")
        #expect(calls.first?.1.contains("lint") == true)
        #expect(calls.first?.1.contains("--config") == true)
        #expect(calls.first?.1.contains(configURL.path) == true)
        #expect(calls.first?.1.last == tempDir.path)
    }

    @Test("SwiftLintCLI executeLintCommand skips missing config")
    func testExecuteLintCommandSkipsMissingConfig() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data())
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let missingConfigURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeLintCommand(configPath: missingConfigURL, workspacePath: tempDir)

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.1.contains("--config") == false)
        #expect(calls.first?.1.last == tempDir.path)
    }

    @Test("SwiftLintCLI executeRulesCommand uses runner")
    func testExecuteRulesCommandUsesRunner() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("rules".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeRulesCommand()

        let calls = await recorder.calls
        #expect(calls.first?.0 == "swiftlint")
        #expect(calls.first?.1 == ["rules"])
    }

    @Test("SwiftLintCLI executeRuleDetailCommand uses runner")
    func testExecuteRuleDetailCommandUsesRunner() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("rule".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeRuleDetailCommand(ruleId: "some_rule")

        let calls = await recorder.calls
        #expect(calls.first?.1 == ["rules", "some_rule"])
    }

    @Test("SwiftLintCLI detects SwiftLint path and caches it")
    func testDetectSwiftLintPathCaching() async throws {
        actor FileExistsMap {
            var values: [String: Bool]
            init(values: [String: Bool]) {
                self.values = values
            }
            func set(_ path: String, _ value: Bool) {
                values[path] = value
            }
            func get(_ path: String) -> Bool {
                values[path] ?? false
            }
        }

        let map = FileExistsMap(values: [
            "/opt/homebrew/bin/swiftlint": true,
            "/usr/local/bin/swiftlint": false
        ])
        let fileExists: SwiftLintFileExists = { path in
            await map.get(path)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(
            cacheManager: cacheManager,
            fileExists: fileExists
        )

        let first = try await cli.detectSwiftLintPath()
        #expect(first.path == "/opt/homebrew/bin/swiftlint")

        await map.set("/opt/homebrew/bin/swiftlint", false)
        await map.set("/usr/local/bin/swiftlint", true)
        let second = try await cli.detectSwiftLintPath()
        #expect(second.path == "/usr/local/bin/swiftlint")
    }

    @Test("SwiftLintCLI falls back to shell runner when path missing")
    func testFallbackToShellRunner() async throws {
        let fileExists: SwiftLintFileExists = { _ in false }
        let shellRunner: SwiftLintShellRunner = { command, _, _ in
            #expect(command.contains("swiftlint rules") == true)
            return (Data("ok".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(
            cacheManager: cacheManager,
            fileExists: fileExists,
            shellRunner: shellRunner
        )

        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLI uses process runner for direct execution")
    func testProcessRunnerDirectExecution() async throws {
        let fileExists: SwiftLintFileExists = { path in
            path == "/opt/homebrew/bin/swiftlint"
        }
        let processRunner: SwiftLintProcessRunner = { url, arguments, environment in
            #expect(url.path == "/opt/homebrew/bin/swiftlint")
            #expect(arguments.contains("rules") == true)
            #expect(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
            return (Data("ok".utf8), Data("warning: ignore".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(
            cacheManager: cacheManager,
            fileExists: fileExists,
            processRunner: processRunner
        )

        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLI buildEnvironment adds Homebrew paths")
    func testBuildEnvironmentAddsPaths() {
        let base = ["PATH": "/usr/bin:/bin"]
        let env = SwiftLintCLI.buildEnvironment(base: base)
        #expect(env["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/local/bin:") == true)
    }

    @Test("SwiftLintCLI buildEnvironment sets default PATH")
    func testBuildEnvironmentSetsDefault() {
        let env = SwiftLintCLI.buildEnvironment(base: [:])
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    }

    @Test("SwiftLintCLI builds shell command with escaping")
    func testBuildShellCommandEscaping() {
        let command = SwiftLintCLI.buildShellCommand(
            command: "swiftlint",
            arguments: ["rules", "path with spaces", "quote'arg"]
        )
        #expect(command.contains("'path with spaces'") == true)
        #expect(command.contains("'quote'\"'\"'arg'") == true)
    }

    @Test("SwiftLintCLI buildLintArguments includes config when present")
    func testBuildLintArgumentsIncludesConfig() async {
        let fileExists: SwiftLintFileExists = { _ in true }
        let configURL = URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        let workspaceURL = URL(fileURLWithPath: "/tmp/project")
        let args = await SwiftLintCLI.buildLintArguments(
            configPath: configURL,
            workspacePath: workspaceURL,
            fileExists: fileExists
        )
        #expect(args.contains("--config") == true)
        #expect(args.contains(configURL.path) == true)
        #expect(args.last == workspaceURL.path)
    }

    @Test("SwiftLintCLI buildLintArguments skips config when missing")
    func testBuildLintArgumentsSkipsMissingConfig() async {
        let fileExists: SwiftLintFileExists = { _ in false }
        let configURL = URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        let workspaceURL = URL(fileURLWithPath: "/tmp/project")
        let args = await SwiftLintCLI.buildLintArguments(
            configPath: configURL,
            workspacePath: workspaceURL,
            fileExists: fileExists
        )
        #expect(args.contains("--config") == false)
        #expect(args.last == workspaceURL.path)
    }

    @Test("SwiftLintCLI detectSwiftLintPath throws when missing")
    func testDetectSwiftLintPathNotFound() async {
        let fileExists: SwiftLintFileExists = { _ in false }
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, fileExists: fileExists)

        do {
            _ = try await cli.detectSwiftLintPath()
            #expect(false, "Expected notFound error")
        } catch let error as SwiftLintError {
            switch error {
            case .notFound:
                #expect(true)
            default:
                #expect(false, "Expected notFound error")
            }
        } catch {
            #expect(false, "Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLI readWithTimeout returns data on time")
    func testReadWithTimeoutSuccess() async throws {
        let read: @Sendable () async -> (Data, Data) = {
            (Data("ok".utf8), Data("warn".utf8))
        }
        let onTimeout: @Sendable () async -> Void = { }
        let timeoutResult = try await SwiftLintCLI.readWithTimeout(
            timeoutSeconds: 1,
            read: read,
            onTimeout: onTimeout
        )
        #expect(String(data: timeoutResult.stdout, encoding: .utf8) == "ok")
        #expect(String(data: timeoutResult.stderr, encoding: .utf8) == "warn")
        #expect(timeoutResult.didTimeout == false)
    }

    @Test("SwiftLintCLI readWithTimeout handles timeout")
    func testReadWithTimeoutTimeout() async throws {
        final class HangGate: @unchecked Sendable {
            private var continuation: CheckedContinuation<Void, Never>?
            private let lock = NSLock()

            func wait() async {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    self.continuation = continuation
                    lock.unlock()
                }
            }

            func open() {
                lock.lock()
                continuation?.resume()
                continuation = nil
                lock.unlock()
            }
        }

        let gate = HangGate()
        let read: @Sendable () async -> (Data, Data) = {
            return await withTaskCancellationHandler {
                await gate.wait()
                return (Data(), Data())
            } onCancel: {
                gate.open()
            }
        }
        actor TimeoutTracker {
            var didTimeout = false
            func mark() { didTimeout = true }
        }
        let tracker = TimeoutTracker()
        let onTimeout: @Sendable () async -> Void = {
            await tracker.mark()
        }

        let timeoutResult = try await SwiftLintCLI.readWithTimeout(
            timeoutSeconds: 1,
            read: read,
            onTimeout: onTimeout
        )
        #expect(timeoutResult.stdout.isEmpty == true)
        #expect(timeoutResult.stderr.isEmpty == true)
        #expect(timeoutResult.didTimeout == true)
        let didTimeout = await tracker.didTimeout
        #expect(didTimeout == true)
    }

    @Test("SwiftLintCLI readChunks accumulates data")
    func testReadChunksAccumulation() async {
        final class ChunkSource: @unchecked Sendable {
            private var chunks: [Data]
            private let lock = NSLock()
            
            init(chunks: [Data]) {
                self.chunks = chunks
            }
            
            func next() -> Data {
                lock.lock()
                defer { lock.unlock() }
                if chunks.isEmpty { return Data() }
                return chunks.removeFirst()
            }
        }
        let source = ChunkSource(chunks: [
            Data("one".utf8),
            Data("two".utf8),
            Data()
        ])
        let read: @Sendable () -> Data = {
            source.next()
        }
        let sleep: @Sendable (UInt64) async -> Void = { _ in }
        let data = await SwiftLintCLI.readChunks(read: read, sleep: sleep, intervalNs: 1)
        #expect(String(data: data, encoding: .utf8) == "onetwo")
    }

    @Test("SwiftLintCLI treats command not found as notFound")
    func testCommandNotFoundError() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data(), Data("swiftlint: command not found".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.executeRulesCommand()
            #expect(false, "Expected notFound error")
        } catch let error as SwiftLintError {
            switch error {
            case .notFound:
                #expect(true)
            default:
                #expect(false, "Expected notFound error")
            }
        } catch {
            #expect(false, "Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLI treats stderr error as executionFailed")
    func testExecutionFailedOnErrorStderr() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data(), Data("error: bad things happened".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.executeRulesCommand()
            #expect(false, "Expected executionFailed error")
        } catch let error as SwiftLintError {
            switch error {
            case .executionFailed:
                #expect(true)
            default:
                #expect(false, "Expected executionFailed error")
            }
        } catch {
            #expect(false, "Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLI executeCommandViaShell falls back to shell execution")
    func testExecuteCommandViaShellFallbackUsesShell() async throws {
        let fileExists: SwiftLintFileExists = { _ in false }
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, fileExists: fileExists)

        let output = try await cli.executeCommandViaShell(command: "echo", arguments: ["hello"])
        let outputString = String(data: output, encoding: .utf8)
        #expect(outputString?.contains("hello") == true)
    }

    @Test("SwiftLintCLI ignores warning stderr")
    func testWarningStderrDoesNotFail() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data("ok".utf8), Data("warning: something".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLI ignores invalid rule identifier stderr")
    func testInvalidRuleIdentifierDoesNotFail() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data("ok".utf8), Data("error: is not a valid rule identifier".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let output = try await cli.executeRuleDetailCommand(ruleId: "unknown_rule")
        #expect(String(data: output, encoding: .utf8) == "ok")
    }
    
    @Test("SwiftLintCLI generateDocsForRule uses cached docs")
    func testGenerateDocsUsesCache() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let docsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITestsDocs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        
        let ruleId = "test_rule"
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        try Data("Cached docs".utf8).write(to: docFile)
        
        try cacheManager.saveDocsDirectory(docsDir)
        try cacheManager.saveSwiftLintVersion("1.0.0")
        
        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return (Data("1.0.0\n".utf8), Data())
            }
            return (Data(), Data())
        }
        
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Cached docs")
    }

    @Test("SwiftLintCLI generateDocsForRule reads existing docs directory")
    func testGenerateDocsUsesExistingDocs() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let ruleId = "existing_rule"
        let version = "9.9.9"

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let docsDir = appSupport
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent("rule_docs", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        try Data("Existing docs".utf8).write(to: docFile)

        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return (Data("\(version)\n".utf8), Data())
            }
            return (Data(), Data())
        }

        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Existing docs")
    }

    @Test("SwiftLintCLI generateDocsForRule creates docs after generate-docs")
    func testGenerateDocsCreatesDocs() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let ruleId = "generated_rule"
        let version = "8.8.8"

        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return (Data("\(version)\n".utf8), Data())
            }
            if let pathIndex = arguments.firstIndex(of: "--path"),
               arguments.contains("generate-docs"),
               arguments.indices.contains(pathIndex + 1) {
                let docsDir = URL(fileURLWithPath: arguments[pathIndex + 1], isDirectory: true)
                try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
                let docFile = docsDir.appendingPathComponent("\(ruleId).md")
                try? Data("Generated docs".utf8).write(to: docFile)
            }
            return (Data(), Data())
        }

        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Generated docs")
    }
}
