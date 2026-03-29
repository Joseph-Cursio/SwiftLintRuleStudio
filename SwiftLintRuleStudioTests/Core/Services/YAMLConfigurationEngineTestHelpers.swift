import Foundation
@testable import SwiftLIntRuleStudio

enum YAMLConfigurationEngineTestHelpers {
    static func withEngine<T: Sendable>(
        configPath: URL,
        operation: @MainActor (YAMLConfigurationEngine) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configPath)
            return try operation(engine)
        }
    }

    static func createTempConfigFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configFile, atomically: true, encoding: .utf8)
        return configFile
    }

    static func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
