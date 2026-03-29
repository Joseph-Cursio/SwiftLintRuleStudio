//
//  WorkspaceManagerValidationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Workspace validation tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct WorkspaceManagerValidationTests {
    @Test("WorkspaceManager accepts workspace with deep Swift file")
    func testWorkspaceWithDeepSwiftFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nestedDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let swiftFile = nestedDir.appendingPathComponent("Test.swift")
        try "struct Test {}".write(to: swiftFile, atomically: true, encoding: .utf8)

        let currentWorkspace = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return manager.currentWorkspace
        }

        #expect(currentWorkspace != nil)
    }

    @Test("WorkspaceManager ignores .build Swift files when validating")
    func testWorkspaceIgnoresBuildDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let buildDir = tempDir.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let swiftFile = buildDir.appendingPathComponent("Test.swift")
        try "struct Test {}".write(to: swiftFile, atomically: true, encoding: .utf8)

        await #expect(throws: WorkspaceError.self) {
            try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
                try manager.openWorkspace(at: tempDir)
            }
        }
    }
}
