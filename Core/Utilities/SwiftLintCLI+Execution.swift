import Foundation

extension SwiftLintCLI {
    /// Execute command - try direct execution first, fall back to shell if needed
    /// Direct execution is faster and avoids shell overhead
    func executeCommandViaShell(command: String, arguments: [String]) async throws -> Data {
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
                let message = "SwiftLint command timed out after \(timeoutSeconds) seconds."
                throw SwiftLintError.executionFailed(message: message)
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
            let isError = lowercased.contains("error:")
            let isWarning = lowercased.contains("warning:")
            let isInvalidRule = lowercased.contains("is not a valid rule identifier")
            if isError && !isWarning && !isInvalidRule {
                throw SwiftLintError.executionFailed(message: errorMessage)
            }
        }
        
        return stdout
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
                    let message = "SwiftLint command timed out after \(timeoutSeconds) seconds."
                    throw SwiftLintError.executionFailed(message: message)
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
