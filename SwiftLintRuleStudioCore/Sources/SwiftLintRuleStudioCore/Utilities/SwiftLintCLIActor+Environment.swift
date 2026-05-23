import Foundation

public extension SwiftLintCLIActor {
    /// Builds a process environment dictionary with Homebrew paths prepended to PATH
    nonisolated static func buildEnvironment(base: [String: String]) -> [String: String] {
        var environment = base
        if let currentPath = environment["PATH"], !currentPath.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        } else if environment["PATH"] == nil {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        return environment
    }

    /// Joins command and arguments into a single shell-safe command string
    nonisolated static func buildShellCommand(command: String, arguments: [String]) -> String {
        var commandParts = [command]
        commandParts.append(contentsOf: arguments)
        let escapedParts = commandParts.map { escapeShellArgument($0) }
        return escapedParts.joined(separator: " ")
    }

    /// Wraps a string in single quotes if it contains special shell characters
    nonisolated static func escapeShellArgument(_ value: String) -> String {
        if value.contains(" ") || value.contains("'") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
            return "'\(escaped)'"
        }
        return value
    }

    /// Builds the argument array for `swiftlint lint --reporter json`
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
}
