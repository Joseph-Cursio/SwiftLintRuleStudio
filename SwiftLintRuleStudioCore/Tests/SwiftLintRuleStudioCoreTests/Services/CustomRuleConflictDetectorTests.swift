//
//  CustomRuleConflictDetectorTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for CustomRuleConflictDetector — flagging custom rules that share a
//  name with a built-in SwiftLint rule.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct CustomRuleConflictDetectorTests {

    private static let sourceConfig = #"""
    opt_in_rules:
      - force_unwrapping
    custom_rules:
      leading_whitespace:
        name: Tabs
        message: Use tab indentation
        regex: ^\t* +\t*\S
        severity: error
      tab_indentation:
        name: Tabs (renamed)
        regex: ^\t* +\t*\S
        severity: error
    """#

    private func makeConfig() throws -> YAMLConfig {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConflictTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let configPath = dir.appendingPathComponent(".swiftlint.yml")
        try Self.sourceConfig.write(to: configPath, atomically: true, encoding: .utf8)
        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        return engine.getConfig()
    }

    // MARK: - Pure conflict detection

    @Test("a custom rule sharing a built-in name is flagged; a unique one is not")
    func testConflictDetection() {
        let detector = CustomRuleConflictDetector()
        let conflicts = detector.conflicts(
            customRuleIdentifiers: ["leading_whitespace", "tab_indentation"],
            builtInRuleIdentifiers: ["leading_whitespace", "force_cast", "todo"]
        )
        #expect(conflicts.map(\.ruleIdentifier) == ["leading_whitespace"])
    }

    @Test("no conflicts when nothing collides")
    func testNoConflicts() {
        let detector = CustomRuleConflictDetector()
        let conflicts = detector.conflicts(
            customRuleIdentifiers: ["tab_indentation"],
            builtInRuleIdentifiers: ["leading_whitespace", "force_cast"]
        )
        #expect(conflicts.isEmpty)
    }

    @Test("the advisory softly suggests renaming")
    func testAdvisoryMessage() {
        let conflict = CustomRuleConflict(ruleIdentifier: "leading_whitespace")
        #expect(conflict.message.contains("leading_whitespace"))
        #expect(conflict.message.contains("built-in"))
        #expect(conflict.message.contains("consider renaming"))
        // Soft, not imperative.
        #expect(conflict.message.contains("you must") == false)
    }

    // MARK: - Extraction from a parsed config

    @Test("custom rule identifiers are read from the parsed config")
    func testCustomRuleIdentifiers() throws {
        let config = try makeConfig()
        let detector = CustomRuleConflictDetector()
        let identifiers = detector.customRuleIdentifiers(in: config)
        #expect(identifiers == ["leading_whitespace", "tab_indentation"])
    }

    @Test("end-to-end: detect the leading_whitespace collision in a real config")
    func testConflictsInConfig() throws {
        let config = try makeConfig()
        let detector = CustomRuleConflictDetector()
        let conflicts = detector.conflicts(
            in: config,
            builtInRuleIdentifiers: ["leading_whitespace", "trailing_whitespace", "force_cast"]
        )
        #expect(conflicts.map(\.ruleIdentifier) == ["leading_whitespace"])
    }
}
