//
//  ConfigComparisonServiceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ConfigComparisonService
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

struct ConfigComparisonServiceTests {

    // MARK: - Helpers

    private func createTempConfig(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComparisonTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func cleanup(_ configPath: URL) {
        try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent())
    }

    // MARK: - Tests

    @Test("Identical configs show no differences")
    @MainActor
    func testIdenticalConfigs() throws {
        let content = "rules:\n  force_cast: true\n  line_length: true\n"
        let config1 = try createTempConfig(content: content)
        let config2 = try createTempConfig(content: content)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "Project A",
            config2: config2, label2: "Project B"
        )

        #expect(result.onlyInFirst.isEmpty)
        #expect(result.onlyInSecond.isEmpty)
        #expect(result.inBothDifferent.isEmpty)
        #expect(result.inBothSame.count == 2)
    }

    @Test("Different enabled rules detected")
    @MainActor
    func testDifferentEnabledRules() throws {
        let content1 = "rules:\n  force_cast: true\n"
        let content2 = "rules:\n  line_length: true\n"
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "Project A",
            config2: config2, label2: "Project B"
        )

        #expect(result.onlyInFirst.contains("force_cast"))
        #expect(result.onlyInSecond.contains("line_length"))
    }

    @Test("Different severities detected")
    @MainActor
    func testDifferentSeverities() throws {
        let content1 = "rules:\n  force_cast:\n    severity: warning\n"
        let content2 = "rules:\n  force_cast:\n    severity: error\n"
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "Project A",
            config2: config2, label2: "Project B"
        )

        #expect(result.inBothDifferent.count == 1)
        #expect(result.inBothDifferent[0].ruleId == "force_cast")
        #expect(!result.inBothDifferent[0].differences.isEmpty)
    }

    @Test("Different parameters detected")
    @MainActor
    func testDifferentParameters() throws {
        let content1 = "rules:\n  line_length:\n    warning: 120\n"
        let content2 = "rules:\n  line_length:\n    warning: 200\n"
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "Project A",
            config2: config2, label2: "Project B"
        )

        #expect(result.inBothDifferent.count == 1)
        #expect(result.inBothDifferent[0].ruleId == "line_length")
    }

    @Test("Empty vs populated config")
    @MainActor
    func testEmptyVsPopulated() throws {
        let content1 = "rules: {}"
        let content2 = "rules:\n  force_cast: true\n  line_length: true\n"
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "Empty",
            config2: config2, label2: "Populated"
        )

        #expect(result.onlyInFirst.isEmpty)
        #expect(result.onlyInSecond.count == 2)
        #expect(result.inBothDifferent.isEmpty)
        #expect(result.inBothSame.isEmpty)
    }

    @Test("Total differences count")
    @MainActor
    func testTotalDifferencesCount() throws {
        let content1 = "rules:\n  force_cast: true\n  trailing_whitespace:\n    severity: warning\n"
        let content2 = "rules:\n  line_length: true\n  trailing_whitespace:\n    severity: error\n"
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "Project A",
            config2: config2, label2: "Project B"
        )

        // 1 only in first + 1 only in second + 1 different = 3
        #expect(result.totalDifferences == 3)
    }

    @Test("Diff contains YAML before and after")
    @MainActor
    func testDiffContainsYAML() throws {
        let content1 = "rules:\n  force_cast: true\n"
        let content2 = "rules:\n  line_length: true\n"
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }

        let service = ConfigComparisonService()
        let result = try service.compare(
            config1: config1, label1: "A",
            config2: config2, label2: "B"
        )

        #expect(!result.diff.before.isEmpty)
        #expect(!result.diff.after.isEmpty)
        #expect(result.diff.before.contains("force_cast"))
        #expect(result.diff.after.contains("line_length"))
    }
}
