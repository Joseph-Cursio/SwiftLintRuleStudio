//
//  ImpactSimulatorTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for ImpactSimulator tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

public enum ImpactSimulatorTestHelpers {
    public static func withImpactSimulator<T: Sendable>(
        swiftLintCLI: SwiftLintCLIProtocol,
        operation: @escaping (ImpactSimulator) async throws -> T
    ) async throws -> T {
        let simulator = ImpactSimulator(swiftLintCLI: swiftLintCLI)
        return try await operation(simulator)
    }

    public static func createTempWorkspaceDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    public static func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public static func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public static func createMockSwiftLintCLIActor(violations: [Violation] = []) async -> MockSwiftLintCLIActor {
        let mockCLI = MockSwiftLintCLIActor()
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
