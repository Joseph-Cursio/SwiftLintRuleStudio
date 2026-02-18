//
//  ImpactSimulatorTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for ImpactSimulator tests
//

import Foundation
@testable import SwiftLIntRuleStudio

enum ImpactSimulatorTestHelpers {
    static func withImpactSimulator<T: Sendable>(
        swiftLintCLI: SwiftLintCLIProtocol,
        operation: @MainActor @escaping (ImpactSimulator) async throws -> T
    ) async throws -> T {
        return try await Task { @MainActor in
            let simulator = ImpactSimulator(swiftLintCLI: swiftLintCLI)
            return try await operation(simulator)
        }.value
    }

    static func createTempWorkspaceDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    static func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func createMockSwiftLintCLI(violations: [Violation] = []) async -> MockSwiftLintCLI {
        let mockCLI = MockSwiftLintCLI()
        let jsonArray = violations.map { violation -> [String: Any] in
            [
                "file": violation.filePath,
                "line": violation.line,
                "character": violation.column ?? 0,
                "severity": violation.severity.rawValue,
                "rule_id": violation.ruleID,
                "reason": violation.message
            ]
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray)
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            jsonData ?? Data()
        }
        return mockCLI
    }
}
