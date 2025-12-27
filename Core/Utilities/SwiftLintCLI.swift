//
//  SwiftLintCLI.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

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
    
    init(cacheManager: CacheManagerProtocol? = nil) {
        // Use provided cache manager or create a default one
        // Store as concrete CacheManager type to avoid protocol existential isolation issues
        // CacheManager is a struct (value type) and Sendable, so it can cross actor boundaries
        if let provided = cacheManager as? CacheManager {
            self.cacheManager = provided
        } else {
            self.cacheManager = CacheManager()
        }
    }
    
    // swiftlint:disable:next async_without_await
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func detectSwiftLintPath() async throws -> URL { // swiftlint:disable:this async_without_await
        // Check cache first (fast path) - synchronous check is fine for cached paths
        if let cached = cachedSwiftLintPath, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        } else if cachedSwiftLintPath != nil {
            cachedSwiftLintPath = nil
        }
        
        // Try common locations - synchronous checks should be instant for local paths
        // These are standard system paths, not network mounts, so they should be fast
        let possiblePaths = [
            "/opt/homebrew/bin/swiftlint",  // Apple Silicon Homebrew (most common)
            "/usr/local/bin/swiftlint",     // Intel Homebrew
            "/usr/bin/swiftlint",           // System installation
        ]
        
        // Check paths synchronously - these are local paths and should be instant
        for pathString in possiblePaths {
            if FileManager.default.fileExists(atPath: pathString) {
                let url = URL(fileURLWithPath: pathString)
                cachedSwiftLintPath = url
                return url
            }
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
        
        // Check cached version
        let cachedVersion = try? cacheManager.getCachedSwiftLintVersion()
        
        // Check if we have cached docs directory and version matches
        if let cachedVersion = cachedVersion,
           cachedVersion == currentVersion,
           let cachedDocsDir = cacheManager.getCachedDocsDirectory() {
            let docFile = cachedDocsDir.appendingPathComponent("\(ruleId).md")
            
            // Try to read from cache first
            if FileManager.default.fileExists(atPath: docFile.path) {
                // Wait longer for file system sync (up to 2 seconds)
                var attempts = 0
                while attempts < 20 {
                    if let content = try? String(contentsOf: docFile, encoding: .utf8), !content.isEmpty {
                        print("✅ Using cached documentation for \(ruleId)")
                        return content
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    attempts += 1
                }
            }
        }
        
        // Version changed or cache missing - generate new docs
        print("🔄 Generating new documentation (version: \(currentVersion))")
        
        // Use a persistent directory in app support instead of temp
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let docsDir = appSupport
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent("rule_docs", isDirectory: true)
            .appendingPathComponent(currentVersion, isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        
        // Check if docs already exist for this version (another process might have generated them)
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        if FileManager.default.fileExists(atPath: docFile.path) {
            // Wait longer for file system sync (up to 2 seconds)
            var attempts = 0
            while attempts < 20 {
                if let content = try? String(contentsOf: docFile, encoding: .utf8), !content.isEmpty {
                    print("✅ Using existing documentation for \(ruleId)")
                    // Cache the directory and version
                    try? cacheManager.saveDocsDirectory(docsDir)
                    try? cacheManager.saveSwiftLintVersion(currentVersion)
                    return content
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                attempts += 1
            }
        }
        
        // Generate docs - generate docs for ALL rules (not just enabled ones)
        // This ensures opt-in rules like empty_count have their documentation and examples
        print("⏳ Running generate-docs (this may take a moment for all rules)...")
        _ = try await executeCommandViaShell(command: "swiftlint", arguments: [
            "generate-docs",
            "--path", docsDir.path
        ])
        
        // Wait longer for file system to sync (generate-docs might have just finished writing)
        // Increased timeout: up to 5 seconds (50 attempts × 0.1s)
        var attempts = 0
        while !FileManager.default.fileExists(atPath: docFile.path) && attempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }
        
        guard FileManager.default.fileExists(atPath: docFile.path) else {
            throw SwiftLintError.executionFailed(message: "Documentation file not found for rule: \(ruleId) after generation")
        }
        
        // Wait for content to be readable (up to 2 more seconds)
        attempts = 0
        var content: String?
        while attempts < 20 {
            content = try? String(contentsOf: docFile, encoding: .utf8)
            if let content = content, !content.isEmpty {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }
        
        guard let finalContent = content, !finalContent.isEmpty else {
            throw SwiftLintError.executionFailed(message: "Could not read documentation file for rule: \(ruleId)")
        }
        
        // Cache the directory and version for future use
        try? cacheManager.saveDocsDirectory(docsDir)
        try? cacheManager.saveSwiftLintVersion(currentVersion)
        print("✅ Generated and cached documentation for \(ruleId)")
        
        return finalContent
    }
    
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        // SwiftLint syntax: swiftlint lint [--config <path>] [--reporter <type>] [<paths>...]
        // The workspace path is a positional argument, not --path
        var arguments = ["lint", "--reporter", "json"]
        
        // Only use config path if the file actually exists
        if let configPath = configPath,
           FileManager.default.fileExists(atPath: configPath.path) {
            arguments.append(contentsOf: ["--config", configPath.path])
        }
        
        // Add workspace path as positional argument (not --path)
        arguments.append(workspacePath.path)
        
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
        let process = Process()
        process.executableURL = swiftLintPath
        process.arguments = arguments
        
        // Set up environment to ensure PATH includes common locations
        var environment = ProcessInfo.processInfo.environment
        // Ensure common Homebrew paths are in PATH
        if let currentPath = environment["PATH"], !currentPath.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        } else if environment["PATH"] == nil {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
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
            // When readDataToEndOfFile() returns, the process has finished and closed the pipe
            // Use longer timeout for large projects (5 minutes = 300 seconds)
            let timeoutSeconds: UInt64 = 300
            let timeoutNanoseconds = timeoutSeconds * 1_000_000_000
            
            var timedOut = false
            
            // Wait for reading to complete (which happens when process finishes and closes pipes)
            // The readDataToEndOfFile() will block until the pipe closes (process finishes)
            do {
                // Wait for output reading with timeout
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Task to wait for output reading to complete
                    group.addTask { @Sendable in
                        // Wait for output to be read (this blocks until pipe closes = process done)
                        _ = await outputTask.value
                        _ = await errorTask.value
                    }
                    
                    // Task for timeout
                    group.addTask { @Sendable in
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                        // Timeout reached - try to terminate
                        process.terminate()
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        process.terminate()
                        print("⏰ Timeout reached")
                        throw SwiftLintError.executionFailed(message: "SwiftLint command timed out after \(timeoutSeconds) seconds.")
                    }
                    
                    // Wait for first task to complete (whichever finishes first)
                    try await group.next()
                    group.cancelAll()
                }
                timedOut = false
            } catch {
                // If timeout task wins, we get an error
                if case SwiftLintError.executionFailed(let msg) = error, msg.contains("timed out") {
                    timedOut = true
                } else {
                    throw error
                }
            }
            
            // Get the output data
            outputData = await outputTask.value
            errorData = await errorTask.value
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️  SwiftLint process completed in \(String(format: "%.2f", elapsed)) seconds")
            
            if timedOut {
                throw SwiftLintError.executionFailed(message: "SwiftLint command timed out after \(timeoutSeconds) seconds. For very large projects, consider analyzing specific files or directories.")
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 4 {
                throw SwiftLintError.executionFailed(message: "SwiftLint executable not found. Please ensure SwiftLint is installed (brew install swiftlint) and accessible.")
            }
            throw SwiftLintError.executionFailed(message: "Failed to execute SwiftLint: \(error.localizedDescription)")
        }
        
        // Output and error data were already read above during the wait
        print("📖 Read \(outputData.count) bytes of output")
        
        // Check exit code - but be careful due to sandboxing restrictions
        // SwiftLint returns exit code 1 when violations are found, which is normal
        // Only treat as error if exit code is not 0 or 1, or if there's an actual error message
        // Note: terminationStatus may throw if process is still running, so we check error output instead
        // Check for errors in stderr output
        // SwiftLint writes warnings to stderr even on success, so we need to be careful
        if !errorData.isEmpty {
            if let errorMessage = String(data: errorData, encoding: .utf8) {
                // Check if it's a "command not found" error
                if errorMessage.contains("command not found") || errorMessage.contains("swiftlint: command not found") {
                    throw SwiftLintError.notFound
                }
                
                // Only throw if it's a real error (not just warnings)
                // SwiftLint writes warnings to stderr even on success
                let lowercased = errorMessage.lowercased()
                if lowercased.contains("error:") && !lowercased.contains("warning:") && !lowercased.contains("is not a valid rule identifier") {
                    throw SwiftLintError.executionFailed(message: errorMessage)
                }
            }
        }
        
        // If we got output, assume success (SwiftLint returns exit code 1 for violations, which is normal)
        // Don't check terminationStatus due to sandboxing restrictions
        
        // SwiftLint may write errors to stderr even when it succeeds (like invalid rule warnings)
        // But we still want to return the JSON output from stdout
        return outputData
    }
    
    /// Fallback: Execute command via shell - works better with sandboxed apps
    /// The shell's PATH will resolve the command name
    private func executeCommandViaShellFallback(command: String, arguments: [String]) async throws -> Data {
        let shellPath = "/bin/zsh"
        
        // Build command string with proper escaping
        var commandParts = [command]
        commandParts.append(contentsOf: arguments)
        
        // Escape arguments that contain spaces or special characters
        let escapedParts = commandParts.map { part in
            // Simple escaping - wrap in single quotes and escape internal quotes
            if part.contains(" ") || part.contains("'") || part.contains("\"") {
                let escaped = part.replacingOccurrences(of: "'", with: "'\"'\"'")
                return "'\(escaped)'"
            }
            return part
        }
        
        let commandString = escapedParts.joined(separator: " ")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", commandString]
        
        // Set up environment to ensure PATH includes common locations
        var environment = ProcessInfo.processInfo.environment
        // Ensure common Homebrew paths are in PATH
        if let currentPath = environment["PATH"], !currentPath.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        } else if environment["PATH"] == nil {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
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
            let timeoutNanoseconds = timeoutSeconds * 1_000_000_000
            
            var timedOut = false
            
            // Read output incrementally as it becomes available
            await withTaskGroup(of: (Bool, Data?, Data?).self) { group in
                // Task to read output incrementally
                group.addTask { @Sendable in
                    // Use separate actors to protect concurrent mutations
                    actor OutputAccumulator {
                        private var data = Data()
                        func append(_ chunk: Data) {
                            data.append(chunk)
                        }
                        func get() -> Data {
                            data
                        }
                    }
                    
                    let outputAccumulator = OutputAccumulator()
                    let errorAccumulator = OutputAccumulator()
                    
                    await withTaskGroup(of: Void.self) { readGroup in
                        readGroup.addTask { @Sendable in
                            while true {
                                let chunk = outputPipe.fileHandleForReading.availableData
                                if chunk.isEmpty {
                                    break
                                }
                                await outputAccumulator.append(chunk)
                                try? await Task.sleep(nanoseconds: 10_000_000)
                            }
                        }
                        
                        readGroup.addTask { @Sendable in
                            while true {
                                let chunk = errorPipe.fileHandleForReading.availableData
                                if chunk.isEmpty {
                                    break
                                }
                                await errorAccumulator.append(chunk)
                                try? await Task.sleep(nanoseconds: 10_000_000)
                            }
                        }
                        
                        await readGroup.waitForAll()
                    }
                    
                    let output = await outputAccumulator.get()
                    let error = await errorAccumulator.get()
                    return (false, output, error)
                }
                
                group.addTask { @Sendable in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    process.terminate()
                    print("⏰ Timeout reached")
                    return (true, nil, nil)
                }
                
                if let result = await group.next() {
                    timedOut = result.0
                    if let output = result.1 {
                        outputData = output
                    }
                    if let error = result.2 {
                        errorData = error
                    }
                }
                group.cancelAll()
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️  SwiftLint process completed in \(String(format: "%.2f", elapsed)) seconds")
            
            if timedOut {
                throw SwiftLintError.executionFailed(message: "SwiftLint command timed out after \(timeoutSeconds) seconds.")
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 4 {
                throw SwiftLintError.executionFailed(message: "SwiftLint executable not found.")
            }
            throw SwiftLintError.executionFailed(message: "Failed to execute SwiftLint: \(error.localizedDescription)")
        }
        
        // Check for errors in stderr output
        // Don't check terminationStatus due to sandboxing - it can throw if process is still running
        if !errorData.isEmpty {
            if let errorMessage = String(data: errorData, encoding: .utf8) {
                if errorMessage.contains("command not found") || errorMessage.contains("swiftlint: command not found") {
                    throw SwiftLintError.notFound
                }
                
                // Only throw if it's a real error (not just warnings)
                let lowercased = errorMessage.lowercased()
                if lowercased.contains("error:") && !lowercased.contains("warning:") && !lowercased.contains("is not a valid rule identifier") {
                    throw SwiftLintError.executionFailed(message: errorMessage)
                }
            }
        }
        
        return outputData
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

