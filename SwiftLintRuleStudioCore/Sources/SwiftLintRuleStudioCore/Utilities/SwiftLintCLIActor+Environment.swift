import Foundation

public extension SwiftLintCLIActor {
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
