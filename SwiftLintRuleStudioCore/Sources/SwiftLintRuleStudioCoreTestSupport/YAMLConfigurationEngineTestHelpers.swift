import Foundation
@testable import SwiftLintRuleStudioCore

/// Test helpers for YAML configuration engine tests
public enum YAMLConfigurationEngineTestHelpers {
    /// Create a temporary engine and run an operation against it
    public static func withEngine<T: Sendable>(
        configPath: URL,
        operation: (YAMLConfigurationEngine) throws -> T
    ) throws -> T {
        let engine = YAMLConfigurationEngine(configPath: configPath)
        return try operation(engine)
    }

    /// Create a temporary `.swiftlint.yml` file with the given content
    public static func createTempConfigFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configFile, atomically: true, encoding: .utf8)
        return configFile
    }

    /// Remove the temporary config file and its parent directory
    public static func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
