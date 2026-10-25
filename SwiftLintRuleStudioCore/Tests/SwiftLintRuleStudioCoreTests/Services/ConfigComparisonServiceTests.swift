//
//  ConfigComparisonServiceTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigComparisonService: two configs compared by what SwiftLint does with each.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
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

    private func compare(
        _ content1: String,
        _ content2: String,
        knownRules: [Rule] = []
    ) throws -> ConfigComparisonResult {
        let config1 = try createTempConfig(content: content1)
        let config2 = try createTempConfig(content: content2)
        defer { cleanup(config1); cleanup(config2) }
        return try ConfigComparisonService().compare(
            config1: config1, label1: "Server",
            config2: config2, label2: "Client",
            knownRules: knownRules
        )
    }

    // MARK: - Tests

    @Test("Identical configs show no differences")
    func testIdenticalConfigs() throws {
        let content = "opt_in_rules:\n  - empty_count\nline_length:\n  warning: 120\n"
        let result = try compare(content, content)

        #expect(result.totalDifferences == 0)
        #expect(result.inBothSame == ["empty_count", "line_length"])
    }

    /// The case that showed nothing before: one config switches rules on through a list, the
    /// other through settings blocks, and only settings blocks were compared.
    @Test("Rules switched on through opt_in_rules count, not just settings blocks")
    func testOptInRulesCount() throws {
        let result = try compare(
            "opt_in_rules:\n  - empty_count\nline_length:\n  warning: 160\ndisabled_rules:\n  - todo\n",
            "opt_in_rules:\n  - empty_count\n  - array_init\n  - closure_spacing\nanalyzer_rules:\n  - unused_import\n"
        )

        // todo is disabled under Server and on by default under Client.
        #expect(result.onlyInSecond == ["array_init", "closure_spacing", "todo", "unused_import"])
        #expect(result.onlyInFirst.isEmpty)
        #expect(result.inBothDifferent.map(\.ruleId) == ["line_length"])
    }

    @Test("A rule disabled in one config runs only with the other")
    func testDisabledRules() throws {
        let result = try compare("disabled_rules:\n  - todo\n", "excluded:\n  - Pods\n")

        #expect(result.onlyInSecond == ["todo"])
    }

    @Test("Each differing setting is named with the config that has each value")
    func testSettingDifferences() throws {
        let result = try compare(
            "line_length:\n  warning: 160\n  ignores_urls: true\n",
            "line_length:\n  warning: 120\n  error: 200\n  severity: error\n"
        )

        let diff = try #require(result.inBothDifferent.first)
        #expect(diff.differences == [
            "severity: Server default, Client error",
            "error: only Client sets it (200)",
            "ignores_urls: only Server sets it (true)",
            "warning: Server 160, Client 120"
        ])
    }

    @Test("Excluded and included paths are compared, with included's all-or-some meaning")
    func testPathDifferences() throws {
        let result = try compare(
            "excluded:\n  - .build\n  - Tests\nincluded:\n  - Sources\n",
            "excluded:\n  - build\n"
        )

        #expect(result.pathDifferences == [
            "Excluded only in Server: .build, Tests",
            "Excluded only in Client: build",
            "Server lints only Sources; Client lints every path"
        ])
    }

    @Test("The catalog settles whether a rule named only in disabled_rules was ever on")
    func testCatalog() throws {
        let catalog = [Rule(id: "force_unwrapping", name: "", description: "", category: .lint, isOptIn: true)]

        let guessed = try compare("disabled_rules:\n  - force_unwrapping\n", "excluded:\n  - Pods\n")
        let known = try compare("disabled_rules:\n  - force_unwrapping\n", "excluded:\n  - Pods\n", knownRules: catalog)

        #expect(guessed.onlyInSecond == ["force_unwrapping"])
        #expect(known.onlyInSecond.isEmpty)
    }

    @Test("Nested blocks compare by value, whatever order their keys come out in")
    func testNestedBlocks() throws {
        let content = """
        identifier_name:
          min_length:
            warning: 2
            error: 1
          max_length:
            warning: 40
            error: 60
        type_name:
          min_length:
            warning: 3
            error: 2
        """
        // A dictionary's order differs from one parse to the next, so one run could pass by luck.
        for _ in 0..<20 {
            #expect(try compare(content, content).totalDifferences == 0)
        }

        let changed = content.replacingOccurrences(of: "warning: 40", with: "warning: 50")
        let diff = try #require(try compare(content, changed).inBothDifferent.first)
        #expect(diff.differences == [
            "max_length: Server {error: 60, warning: 40}, Client {error: 60, warning: 50}"
        ])
    }

    @Test("A rule another rule replaced, but which still runs, stays a rule of its own")
    func testReplacedRulesStaySeparate() throws {
        let catalog = [
            Rule(
                id: "multiple_closures_with_trailing_closure",
                name: "",
                description: "",
                category: .style,
                isOptIn: false
            ),
            Rule(id: "trailing_closure", name: "", description: "", category: .style, isOptIn: true)
        ]
        let result = try compare(
            "opt_in_rules:\n  - trailing_closure\ndisabled_rules:\n  - multiple_closures_with_trailing_closure\n",
            "opt_in_rules:\n  - trailing_closure\n",
            knownRules: catalog
        )

        #expect(result.onlyInSecond == ["multiple_closures_with_trailing_closure"])
        #expect(result.onlyInFirst.isEmpty)
        #expect(result.inBothSame == ["trailing_closure"])
    }

    @Test("A rule's old name is the same rule")
    func testAliases() throws {
        let result = try compare("disabled_rules:\n  - variable_name\n", "disabled_rules:\n  - identifier_name\n")

        #expect(result.totalDifferences == 0)
        #expect(result.inBothSame == ["identifier_name"])
    }

    @Test("only_rules and all count the rules they switch without naming them")
    func testOnlyRulesAndAll() throws {
        let catalog = [
            Rule(id: "identifier_name", name: "", description: "", category: .style, isOptIn: false),
            Rule(id: "todo", name: "", description: "", category: .lint, isOptIn: false),
            Rule(id: "empty_count", name: "", description: "", category: .performance, isOptIn: true),
            Rule(id: "array_init", name: "", description: "", category: .lint, isOptIn: true)
        ]

        let only = try compare(
            "only_rules:\n  - identifier_name\n", "opt_in_rules:\n  - empty_count\n", knownRules: catalog
        )
        #expect(only.onlyInFirst.isEmpty)
        #expect(only.onlyInSecond == ["empty_count", "todo"])

        let all = try compare("opt_in_rules:\n  - all\n", "opt_in_rules:\n  - empty_count\n", knownRules: catalog)
        #expect(all.onlyInFirst == ["array_init"])
        #expect(all.onlyInSecond.isEmpty)
    }

    @Test("A rule's levels written as a list are the same as written as a block")
    func testLevelList() throws {
        let block = "type_body_length:\n  warning: 300\n  error: 400\n"

        #expect(try compare("type_body_length: [300, 400]\n", block).totalDifferences == 0)

        let changed = try compare("type_body_length: [300, 400]\n", "type_body_length: [300, 500]\n")
        #expect(changed.inBothDifferent.map(\.differences) == [["error: Server 400, Client 500"]])
        #expect(changed.otherDifferences.isEmpty)
    }

    @Test("Settings the app doesn't model compare by value, whatever order their keys are in")
    func testUnmodelledKeyOrder() throws {
        let result = try compare(
            "custom_rules:\n  no_print:\n    regex: print\n    message: No print\n",
            "custom_rules:\n  no_print:\n    message: No print\n    regex: print\n"
        )

        #expect(result.totalDifferences == 0)
    }

    @Test("Diff contains YAML before and after")
    func testDiffContainsYAML() throws {
        let content1 = "opt_in_rules:\n  - empty_count\n"
        let content2 = "opt_in_rules:\n  - array_init\n"
        let result = try compare(content1, content2)

        #expect(result.diff.before == content1)
        #expect(result.diff.after == content2)
    }
}
