import Foundation

extension SwiftLintCLI {
    /// Execute command - try direct execution first, fall back to shell if needed
    /// Direct execution is faster and avoids shell overhead
    func executeCommandViaShell(command: String, arguments: [String]) async throws -> Data {
        if let commandRunner = commandRunner {
            let (stdout, stderr) = try await commandRunner(command, arguments)
            return try processCommandOutput(stdout: stdout, stderr: stderr)
        }
        
        guard let swiftLintPath = await resolveSwiftLintPath() else {
            return try await executeCommandViaShellFallback(command: command, arguments: arguments)
        }
        return try await runDirectProcess(
            swiftLintPath: swiftLintPath,
            arguments: arguments
        )
    }
    
    /// Fallback: Execute command via shell - works better with sandboxed apps
    /// The shell's PATH will resolve the command name
    private func executeCommandViaShellFallback(command: String, arguments: [String]) async throws -> Data {
        let shellPath = "/bin/zsh"
        
        let commandString = Self.buildShellCommand(command: command, arguments: arguments)
        return try await runShellProcess(shellPath: shellPath, commandString: commandString)
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

private extension SwiftLintCLI {
    func resolveSwiftLintPath() async -> URL? {
        do {
            let path = try await detectSwiftLintPath()
            print("✅ Using SwiftLint at: \(path.path)")
            return path
        } catch {
            print("⚠️  SwiftLint not found in standard paths, using shell execution")
            return nil
        }
    }

    func runDirectProcess(swiftLintPath: URL, arguments: [String]) async throws -> Data {
        let environment = Self.buildEnvironment(base: ProcessInfo.processInfo.environment)
        if let processRunner = processRunner {
            let (stdout, stderr) = try await processRunner(swiftLintPath, arguments, environment)
            return try processCommandOutput(stdout: stdout, stderr: stderr)
        }

        let process = Process()
        process.executableURL = swiftLintPath
        process.arguments = arguments
        process.environment = environment

        let output = try await runProcess(
            process,
            label: "SwiftLint process...",
            useChunkedRead: false
        )
        if output.didTimeout {
            let message = "SwiftLint command timed out after 300 seconds. " +
                "For very large projects, consider analyzing specific files or directories."
            throw SwiftLintError.executionFailed(message: message)
        }
        return try processCommandOutput(stdout: output.stdout, stderr: output.stderr)
    }

    func runShellProcess(shellPath: String, commandString: String) async throws -> Data {
        let environment = Self.buildEnvironment(base: ProcessInfo.processInfo.environment)
        if let shellRunner = shellRunner {
            let (stdout, stderr) = try await shellRunner(commandString, [], environment)
            return try processCommandOutput(stdout: stdout, stderr: stderr)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", commandString]
        process.environment = environment

        let output = try await runProcess(
            process,
            label: "SwiftLint process (via shell)...",
            useChunkedRead: true
        )
        if output.didTimeout {
            throw SwiftLintError.executionFailed(message: "SwiftLint command timed out after 300 seconds.")
        }
        return try processCommandOutput(stdout: output.stdout, stderr: output.stderr)
    }

    struct ProcessOutput {
        let stdout: Data
        let stderr: Data
        let didTimeout: Bool
    }

    func runProcess(
        _ process: Process,
        label: String,
        useChunkedRead: Bool
    ) async throws -> ProcessOutput {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        configureProcess(process, outputPipe: outputPipe, errorPipe: errorPipe)

        let startTime = Date()
        print("🚀 Starting \(label)")

        do {
            try process.run()
            closeWriteEnds(outputPipe: outputPipe, errorPipe: errorPipe)

            let timeoutResult = try await readProcessOutput(
                outputPipe: outputPipe,
                errorPipe: errorPipe,
                useChunkedRead: useChunkedRead,
                onTimeout: { await self.terminateProcess(process) }
            )
            logCompletionTime(startTime: startTime)
            return ProcessOutput(
                stdout: timeoutResult.stdout,
                stderr: timeoutResult.stderr,
                didTimeout: timeoutResult.didTimeout
            )
        } catch {
            throw handleProcessError(error)
        }
    }

    func logCompletionTime(startTime: Date) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("⏱️  SwiftLint process completed in \(String(format: "%.2f", elapsed)) seconds")
    }
}

private extension SwiftLintCLI {
    func configureProcess(_ process: Process, outputPipe: Pipe, errorPipe: Pipe) {
        process.standardOutput = outputPipe
        process.standardError = errorPipe
    }

    func closeWriteEnds(outputPipe: Pipe, errorPipe: Pipe) {
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()
    }

    func readProcessOutput(
        outputPipe: Pipe,
        errorPipe: Pipe,
        useChunkedRead: Bool,
        onTimeout: @Sendable @escaping () async -> Void
    ) async throws -> ReadWithTimeoutResult {
        try await Self.readWithTimeout(
            timeoutSeconds: 300,
            read: {
                if useChunkedRead {
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
                }
                let outputTask = Task.detached {
                    outputPipe.fileHandleForReading.readDataToEndOfFile()
                }
                let errorTask = Task.detached {
                    errorPipe.fileHandleForReading.readDataToEndOfFile()
                }
                return (await outputTask.value, await errorTask.value)
            },
            onTimeout: onTimeout
        )
    }

    func terminateProcess(_ process: Process) async {
        process.terminate()
        try? await Task.sleep(nanoseconds: 100_000_000)
        process.terminate()
    }

    func handleProcessError(_ error: Error) -> SwiftLintError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 4 {
            return SwiftLintError.executionFailed(message: "SwiftLint executable not found.")
        }
        return SwiftLintError.executionFailed(message: "Failed to execute SwiftLint: \(error.localizedDescription)")
    }
}
