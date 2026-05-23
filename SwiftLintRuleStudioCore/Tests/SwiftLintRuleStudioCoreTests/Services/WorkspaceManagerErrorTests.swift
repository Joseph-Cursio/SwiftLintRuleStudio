//
//  WorkspaceManagerErrorTests.swift
//  SwiftLintRuleStudioTests
//
//  Error description tests for WorkspaceManager
//

@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct WorkspaceManagerErrorTests {
    @Test("WorkspaceError provides descriptions and recovery suggestions")
    func testWorkspaceErrorDescriptions() {
        let notDirectory = WorkspaceError.notADirectory
        #expect(notDirectory.errorDescription?.contains("directory") == true)
        #expect(notDirectory.recoverySuggestion?.contains("folder") == true)

        let invalidPath = WorkspaceError.invalidPath
        #expect(invalidPath.errorDescription?.contains("invalid") == true)
        #expect(invalidPath.recoverySuggestion?.contains("different") == true)
    }
}
