//
//  WorkspaceManagerErrorTests.swift
//  SwiftLIntRuleStudioTests
//
//  Error description tests for WorkspaceManager
//

import Testing
@testable import SwiftLIntRuleStudio

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
