//
//  SwiftLintCLI.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

typealias SwiftLintCommandRunner = @Sendable (String, [String]) async throws -> (Data, Data)
typealias SwiftLintFileExists = @Sendable (String) async -> Bool
typealias SwiftLintProcessRunner = @Sendable (URL, [String], [String: String]) async throws -> (Data, Data)
typealias SwiftLintShellRunner = @Sendable (String, [String], [String: String]) async throws -> (Data, Data)

/// Protocol for SwiftLint CLI operations
protocol SwiftLintCLIProtocol {
    func detectSwiftLintPath() async throws -> URL
    func executeRulesCommand() async throws -> Data
    func executeRuleDetailCommand(ruleId: String) async throws -> Data
    func generateDocsForRule(ruleId: String) async throws -> String
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data
    func getVersion() async throws -> String
}

/// Service for executing SwiftLint CLI commands
actor SwiftLintCLI: SwiftLintCLIProtocol {
    private var cachedSwiftLintPath: URL?
    private let cacheManager: CacheManager
    private let commandRunner: SwiftLintCommandRunner?
    private let fileExists: SwiftLintFileExists
    private let processRunner: SwiftLintProcessRunner?
    private let shellRunner: SwiftLintShellRunner?
    
    init(
        cacheManager: CacheManagerProtocol? = nil,
        commandRunner: SwiftLintCommandRunner? = nil,
        fileExists: SwiftLintFileExists? = nil,
        processRunner: SwiftLintProcessRunner? = nil,
        shellRunner: SwiftLintShellRunner? = nil
    ) {
        // Use provided cache manager or create a default one
        // Store as concrete CacheManager type to avoid protocol existential isolation issues
        // CacheManager is a struct (value type) and Sendable, so it can cross actor boundaries
        if let provided = cacheManager as? CacheManager {
            self.cacheManager = provided
        } else {
            self.cacheManager = CacheManager()
        }
        self.commandRunner = commandRunner
        self.fileExists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        self.processRunner = processRunner
        self.shellRunner = shellRunner
    }
    
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func detectSwiftLintPath() async throws -> URL {
        // Check cache first (fast path) - synchronous check is fine for cached paths
        if let cached = cachedSwiftLintPath, await fileExists(cached.path) {
            return cached
        } else if cachedSwiftLintPath != nil {
            cachedSwiftLintPath = nil
        }
        
        // Try common locations - synchronous checks should be instant for local paths
        // These are standard system paths, not network mounts, so they should be fast
        let possiblePaths = [
            "/opt/homebrew/bin/swiftlint",  // Apple Silicon Homebrew (most common)
            "/usr/local/bin/swiftlint",     // Intel Homebrew
            "/usr/bin/swiftlint"            // System installation
        ]
        
        // Check paths synchronously - these are local paths and should be instant
        for pathString in possiblePaths where await fileExists(pathString) {
            let url = URL(fileURLWithPath: pathString)
            cachedSwiftLintPath = url
            return url
        }
        
        // If we get here, SwiftLint wasn't found in common locations
        throw SwiftLintError.notFound
    }
    
    func executeRulesCommand() async throws -> Data {
        // Use "swiftlint" command directly - let shell PATH resolve it
        // This works better with sandboxed apps
        return try await executeCommandViaShell(command: "swiftlint", arguments: ["rules"])
    }
    
    func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        return try await executeCommandViaShell(command: "swiftlint", arguments: ["rules", ruleId])
    }
    
    func generateDocsForRule(ruleId: String) async throws -> String {
        // Check current SwiftLint version
        let currentVersion = try await getVersion()
        print("📋 Current SwiftLint version: \(currentVersion)")
        
        if let cachedContent = await readCachedDocs(ruleId: ruleId, currentVersion: currentVersion) {
            return cachedContent
        }
        
        // Version changed or cache missing - generate new docs
        print("🔄 Generating new documentation (version: \(currentVersion))")
        
        let docsDir = docsDirectory(for: currentVersion)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        
        if let existingContent = await readExistingDocs(
            ruleId: ruleId,
            docsDir: docsDir,
            currentVersion: currentVersion
        ) {
            return existingContent
        }
        
        // Generate docs - generate docs for ALL rules (not just enabled ones)
        // This ensures opt-in rules like empty_count have their documentation and examples
        print("⏳ Running generate-docs (this may take a moment for all rules)...")
        _ = try await executeCommandViaShell(command: "swiftlint", arguments: [
            "generate-docs",
            "--path", docsDir.path
        ])
        
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        let fileExists = await waitForFile(at: docFile, attempts: 50, delayNanoseconds: 100_000_000)
        
        guard fileExists else {
            throw SwiftLintError.executionFailed(message: "Documentation file not found for rule: \(ruleId) after generation")
        }
        
        // Wait for content to be readable (up to 2 more seconds)
        guard let finalContent = await readDocFileWithRetries(
            docFile,
            attempts: 20,
            delayNanoseconds: 100_000_000
        ) else {
            throw SwiftLintError.executionFailed(message: "Could not read documentation file for rule: \(ruleId)")
        }
        
        // Cache the directory and version for future use
        try? cacheManager.saveDocsDirectory(docsDir)
        try? cacheManager.saveSwiftLintVersion(currentVersion)
        print("✅ Generated and cached documentation for \(ruleId)")
        
        return finalContent
    }

    private func docsDirectory(for version: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent("rule_docs", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private func readCachedDocs(ruleId: String, currentVersion: String) async -> String? {
        guard let cachedVersion = try? cacheManager.getCachedSwiftLintVersion(),
              cachedVersion == currentVersion,
              let cachedDocsDir = cacheManager.getCachedDocsDirectory() else {
            return nil
        }
        let docFile = cachedDocsDir.appendingPathComponent("\(ruleId).md")
        guard FileManager.default.fileExists(atPath: docFile.path) else { return nil }
        if let content = await readDocFileWithRetries(docFile, attempts: 20, delayNanoseconds: 100_000_000) {
            print("✅ Using cached documentation for \(ruleId)")
            return content
        }
        return nil
    }

    private func readExistingDocs(ruleId: String, docsDir: URL, currentVersion: String) async -> String? {
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        guard FileManager.default.fileExists(atPath: docFile.path) else { return nil }
        if let content = await readDocFileWithRetries(docFile, attempts: 20, delayNanoseconds: 100_000_000) {
            print("✅ Using existing documentation for \(ruleId)")
            try? cacheManager.saveDocsDirectory(docsDir)
            try? cacheManager.saveSwiftLintVersion(currentVersion)
            return content
        }
        return nil
    }

    private func waitForFile(at fileURL: URL, attempts: Int, delayNanoseconds: UInt64) async -> Bool {
        var remaining = attempts
        while remaining > 0 {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            remaining -= 1
        }
        return false
    }

    private func readDocFileWithRetries(
        _ fileURL: URL,
        attempts: Int,
        delayNanoseconds: UInt64
    ) async -> String? {
        var remaining = attempts
        while remaining > 0 {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty {
                return content
            }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            remaining -= 1
        }
        return nil
    }
    
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        let arguments = await Self.buildLintArguments(
            configPath: configPath,
            workspacePath: workspacePath,
            fileExists: fileExists
        )
        return try await executeCommandViaShell(command: "swiftlint", arguments: arguments)
    }
    
    func getVersion() async throws -> String {
        let data = try await executeCommandViaShell(command: "swiftlint", arguments: ["version"])
        guard let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SwiftLintError.invalidVersion
        }
        return version
    }
    
    /// Execute command - try direct execution first, fall back to shell if needed
    /// Direct execution is faster and avoids shell overhead
    private func executeCommandViaShell(command: String, arguments: [String]) async throws -> Data {
        if let commandRunner = commandRunner {
            let (stdout, stderr) = try await commandRunner(command, arguments)
            return try processCommandOutput(stdout: stdout, stderr: stderr)
        }
        
        // Try to find SwiftLint path for direct execution
        let swiftLintPath: URL
        do {
            swiftLintPath = try await detectSwiftLintPath()
            print("✅ Using SwiftLint at: \(swiftLintPath.path)")
        } catch {
            // Fall back to shell if we can't find SwiftLint directly
            print("⚠️  SwiftLint not found in standard paths, using shell execution")
            return try await executeCommandViaShellFallback(command: command, arguments: arguments)
        }
        
        // Execute SwiftLint directly (faster, no shell overhead)
        let environment = Self.buildEnvironment(base: ProcessInfo.processInfo.environment)

        if let processRunner = processRunner {
            let (stdout, stderr) = try await processRunner(swiftLintPath, arguments, environment)
            return try processCommandOutput(stdout: stdout, stderr: stderr)
        }

        let process = Process()
        process.executableURL = swiftLintPath
        process.arguments = arguments
        process.environment = environment
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        var outputData = Data()
        var errorData = Data()
        
        do {
            let startTime = Date()
            print("🚀 Starting SwiftLint process...")
            
            // Start reading output BEFORE running process
            // This prevents the pipe buffer from filling up and blocking SwiftLint
            let outputTask = Task.detached {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            
            let errorTask = Task.detached {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }
            
            try process.run()
            
            // Close write ends immediately so process knows when to finish
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            
            // Wait for reading to complete with timeout
            let timeoutSeconds: UInt64 = 300
            let timeoutResult = try await Self.readWithTimeout(
                timeoutSeconds: timeoutSeconds,
                read: {
                    let stdout = await outputTask.value
                    let stderr = await errorTask.value
                    return (stdout, stderr)
                },
                onTimeout: {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    process.terminate()
                }
            )
            outputData = timeoutResult.stdout
            errorData = timeoutResult.stderr
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️  SwiftLint process completed in \(String(format: "%.2f", elapsed)) seconds")
            
            if timeoutResult.didTimeout {
                let message = "SwiftLint command timed out after \(timeoutSeconds) seconds. " +
                    "For very large projects, consider analyzing specific files or directories."
                throw SwiftLintError.executionFailed(message: message)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 4 {
                let message = "SwiftLint executable not found. " +
                    "Please ensure SwiftLint is installed (brew install swiftlint) and accessible."
                throw SwiftLintError.executionFailed(message: message)
            }
            throw SwiftLintError.executionFailed(message: "Failed to execute SwiftLint: \(error.localizedDescription)")
        }
        
        return try processCommandOutput(stdout: outputData, stderr: errorData)
    }
    
    /// Fallback: Execute command via shell - works better with sandboxed apps
    /// The shell's PATH will resolve the command name
    private func executeCommandViaShellFallback(command: String, arguments: [String]) async throws -> Data {
        let shellPath = "/bin/zsh"
        
        let commandString = Self.buildShellCommand(command: command, arguments: arguments)
        
        let environment = Self.buildEnvironment(base: ProcessInfo.processInfo.environment)

        if let shellRunner = shellRunner {
            let (stdout, stderr) = try await shellRunner(commandString, arguments, environment)
            return try processCommandOutput(stdout: stdout, stderr: stderr)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", commandString]
        process.environment = environment
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        var outputData = Data()
        var errorData = Data()
        
        do {
            let startTime = Date()
            print("🚀 Starting SwiftLint process (via shell)...")
            
            try process.run()
            
            // Close write ends after process starts so it knows when to finish
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            
            // Wait for process to complete by reading output with timeout
            let timeoutSeconds: UInt64 = 300
            let timeoutResult = try await Self.readWithTimeout(
                timeoutSeconds: timeoutSeconds,
                read: {
                    async let stdout = Self.readChunks(
                        read: { outputPipe.fileHandleForReading.availableData },
                        sleep: { try? await Task.sleep(nanoseconds: $0) },
                        intervalNs: 10_000_000
                    )
                    async let stderr = Self.readChunks(
                        read: { errorPipe.fileHandleForReading.availableData },
                        sleep: { try? await Task.sleep(nanoseconds: $0) },
                        intervalNs: 10_000_000
                    )
                    return await (stdout, stderr)
                },
                onTimeout: {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    process.terminate()
                }
            )
            outputData = timeoutResult.stdout
            errorData = timeoutResult.stderr
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️  SwiftLint process completed in \(String(format: "%.2f", elapsed)) seconds")
            
            if timeoutResult.didTimeout {
                throw SwiftLintError.executionFailed(message: "SwiftLint command timed out after \(timeoutSeconds) seconds.")
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 4 {
                throw SwiftLintError.executionFailed(message: "SwiftLint executable not found.")
            }
            throw SwiftLintError.executionFailed(message: "Failed to execute SwiftLint: \(error.localizedDescription)")
        }
        
        return try processCommandOutput(stdout: outputData, stderr: errorData)
    }
    
    private func processCommandOutput(stdout: Data, stderr: Data) throws -> Data {
        print("📖 Read \(stdout.count) bytes of output")
        
        // Check for errors in stderr output (SwiftLint writes warnings to stderr even on success)
        if !stderr.isEmpty, let errorMessage = String(data: stderr, encoding: .utf8) {
            if errorMessage.contains("command not found") || errorMessage.contains("swiftlint: command not found") {
                throw SwiftLintError.notFound
            }
            
            let lowercased = errorMessage.lowercased()
            if lowercased.contains("error:") && !lowercased.contains("warning:") && !lowercased.contains("is not a valid rule identifier") {
                throw SwiftLintError.executionFailed(message: errorMessage)
            }
        }
        
        return stdout
    }

    nonisolated static func buildEnvironment(base: [String: String]) -> [String: String] {
        var environment = base
        if let currentPath = environment["PATH"], !currentPath.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        } else if environment["PATH"] == nil {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        return environment
    }

    nonisolated static func buildShellCommand(command: String, arguments: [String]) -> String {
        var commandParts = [command]
        commandParts.append(contentsOf: arguments)
        let escapedParts = commandParts.map { escapeShellArgument($0) }
        return escapedParts.joined(separator: " ")
    }

    nonisolated static func escapeShellArgument(_ value: String) -> String {
        if value.contains(" ") || value.contains("'") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
            return "'\(escaped)'"
        }
        return value
    }

    nonisolated static func buildLintArguments(
        configPath: URL?,
        workspacePath: URL,
        fileExists: @escaping SwiftLintFileExists
    ) async -> [String] {
        var arguments = ["lint", "--reporter", "json"]
        if let configPath = configPath,
           await fileExists(configPath.path) {
            arguments.append(contentsOf: ["--config", configPath.path])
        }
        arguments.append(workspacePath.path)
        return arguments
    }

    struct ReadWithTimeoutResult {
        let stdout: Data
        let stderr: Data
        let didTimeout: Bool
    }

    nonisolated static func readWithTimeout(
        timeoutSeconds: UInt64,
        read: @escaping @Sendable () async -> (Data, Data),
        onTimeout: @escaping @Sendable () async -> Void
    ) async throws -> ReadWithTimeoutResult {
        let timeoutNanoseconds = timeoutSeconds * 1_000_000_000
        var timedOut = false
        var stdout = Data()
        var stderr = Data()
        
        do {
            try await withThrowingTaskGroup(of: (Data, Data).self) { group in
                group.addTask { @Sendable in
                    await read()
                }
                group.addTask { @Sendable in
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    await onTimeout()
                    print("⏰ Timeout reached")
                    throw SwiftLintError.executionFailed(message: "SwiftLint command timed out after \(timeoutSeconds) seconds.")
                }
                
                if let result = try await group.next() {
                    stdout = result.0
                    stderr = result.1
                }
                group.cancelAll()
            }
            timedOut = false
        } catch {
            if case SwiftLintError.executionFailed(let msg) = error, msg.contains("timed out") {
                timedOut = true
            } else {
                throw error
            }
        }
        
        return ReadWithTimeoutResult(stdout: stdout, stderr: stderr, didTimeout: timedOut)
    }

    nonisolated static func readChunks(
        read: @escaping @Sendable () -> Data,
        sleep: @escaping @Sendable (UInt64) async -> Void,
        intervalNs: UInt64
    ) async -> Data {
        var data = Data()
        while true {
            let chunk = read()
            if chunk.isEmpty {
                break
            }
            data.append(chunk)
            await sleep(intervalNs)
        }
        return data
    }
}

enum SwiftLintError: LocalizedError {
    case notFound
    case invalidVersion
    case executionFailed(message: String)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return """
            SwiftLint not found. Please install SwiftLint using one of these methods:
            
            • Homebrew: brew install swiftlint
            • Mint: mint install realm/SwiftLint
            • CocoaPods: Add to your Podfile
            • Direct download: https://github.com/realm/SwiftLint/releases
            
            After installing, restart SwiftLint Rule Studio.
            """
        case .invalidVersion:
            return "Could not determine SwiftLint version."
        case .executionFailed(let message):
            return "SwiftLint execution failed: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Install SwiftLint using Homebrew: brew install swiftlint"
        default:
            return nil
        }
    }
}
