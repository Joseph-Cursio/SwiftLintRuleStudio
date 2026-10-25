//
//  SimulationWorkspaceEnableTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What the mirror's configs say once a rule is enabled: the rule on in the root configuration,
//  under its deprecated names too, nested configs as Enable leaves them, nothing that writes
//  outside the mirror, and nothing SwiftLint can't read.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceEnableTests {

    // MARK: - Helpers

    private func makeTempFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowEnableTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeShadow(for workspace: URL, applying ruleId: String) throws -> SimulationWorkspace {
        let shadow = try SimulationWorkspaceBuilder()
            .makeWorkspace(for: Workspace(path: workspace), baseConfigPath: nil)
        try shadow.applyRule(ruleId, isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        return shadow
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Deprecated names

    @Test("enabling a rule takes its deprecated names out of disabled_rules, and leaves other rules alone")
    func deprecatedNamesAreRemoved() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["variable_name", "todo"]
        config.onlyRules = ["variable_name", "line_length"]

        ConfigRuleEnabler.enableRule("identifier_name", in: &config, isOptIn: false, isAnalyzer: false)

        #expect(config.disabledRules == ["todo"])
        // only_rules already names the rule by its alias, which SwiftLint reads as the rule.
        #expect(config.onlyRules == ["variable_name", "line_length"])
        let identifierName = Rule(id: "identifier_name", name: "", description: "", category: .style, isOptIn: false)
        #expect(RuleEnablementResolver.isRuleEnabled(identifierName, config: config))
    }

    @Test("the rule is enabled in the configs the root pulls in, not in nested ones")
    func rootConfigurationOnly() throws {
        let base = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("ws")
        try write("disabled_rules:\n  - force_cast\n", to: base.appendingPathComponent("base.yml"))
        try write("parent_config: ../base.yml\n", to: workspace.appendingPathComponent(".swiftlint.yml"))
        try write("disabled_rules:\n  - force_cast\n", to: workspace.appendingPathComponent("Legacy/.swiftlint.yml"))
        try write("let a = 1\n", to: workspace.appendingPathComponent("Legacy/A.swift"))

        let shadow = try makeShadow(for: workspace, applying: "force_cast")
        defer { shadow.cleanup() }

        let parent = shadow.root.deletingLastPathComponent().appendingPathComponent("base.yml")
        #expect(try YAMLConfigurationEngine.loadConfig(at: parent).disabledRules?.contains("force_cast") != true)
        let nested = shadow.root.appendingPathComponent("Legacy/.swiftlint.yml")
        #expect(try YAMLConfigurationEngine.loadConfig(at: nested).disabledRules == ["force_cast"])
    }

    // MARK: - Custom rules

    @Test("custom_rules counts under the name of every custom rule the configs define")
    func customRuleNames() throws {
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "custom_rules:\n  no_number:\n    regex: NSNumber\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write(
            "custom_rules:\n  no_print:\n    regex: print\n",
            to: workspace.appendingPathComponent("Sub/.swiftlint.yml")
        )
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sub/A.swift"))

        let shadow = try makeShadow(for: workspace, applying: "custom_rules")
        defer { shadow.cleanup() }

        #expect(shadow.reportedRuleIds(for: "custom_rules") == ["custom_rules", "no_number", "no_print"])
        #expect(shadow.reportedRuleIds(for: "force_cast") == ["force_cast"])
    }

    // MARK: - Baselines

    @Test("write_baseline is dropped from every config, and baseline points at the user's file")
    func baselineKeys() throws {
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "baseline: baseline.json\nwrite_baseline: /tmp/team-baseline.json\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("write_baseline: nested.json\n", to: workspace.appendingPathComponent("Sub/.swiftlint.yml"))
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sub/A.swift"))

        let shadow = try makeShadow(for: workspace, applying: "force_cast")
        defer { shadow.cleanup() }

        let root = try text(shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(!root.contains("write_baseline"))
        #expect(root.contains(workspace.appendingPathComponent("baseline.json").standardizedFileURL.path))
        #expect(try !text(shadow.root.appendingPathComponent("Sub/.swiftlint.yml")).contains("write_baseline"))
    }

    @Test("a baseline key naming a file by its whole path moves to the mirror, under each spelling there")
    func baselineKeysMove() {
        let places = [
            MirrorBaseline.Place(real: "/Users/me/App", mirror: nil),
            MirrorBaseline.Place(real: "/Users/me/Shared", mirror: "/var/folders/xy/T/m/Shared")
        ]

        #expect(MirrorBaseline.move("Sources/A.swift", to: places) == nil, "relative: right as it is")
        #expect(MirrorBaseline.move("Users/me/App/Sources/A.swift", to: places) == ["Sources/A.swift"])
        let moved = MirrorBaseline.move("Users/me/Shared/S.swift", to: places) ?? []
        #expect(moved.contains("var/folders/xy/T/m/Shared/S.swift"))
        #expect(moved.contains("private/var/folders/xy/T/m/Shared/S.swift"))
        #expect(MirrorBaseline.move("Users/me/Other/O.swift", to: places) == nil)
    }

    // MARK: - Lists SwiftLint doesn't read

    @Test("an included list holding a number is left out of the mirror, as SwiftLint leaves it unread")
    func nonStringListIsDropped() throws {
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "included:\n  - Sources\n  - 2024\nexcluded: Pods\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sources/A.swift"))

        let shadow = try makeShadow(for: workspace, applying: "force_cast")
        defer { shadow.cleanup() }

        let config = try YAMLConfigurationEngine.loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(config.included == nil)
        #expect(config.excluded == ["Pods"])
    }

    // MARK: - Reading back

    @Test("a config SwiftLint can't read back is refused with the path it was written for")
    func unreadableWrite() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bad = folder.appendingPathComponent("bad.yml")
        try write("number_separator:\n  exclude_ranges:\n    - max: 2030\n    min: 1900\n", to: bad)
        let list = folder.appendingPathComponent("list.yml")
        try write("- a\n- b\n", to: list)
        let empty = folder.appendingPathComponent("empty.yml")
        try write("", to: empty)

        let error = #expect(throws: MirrorConfigWriteError.self) {
            try MirrorConfigWriteError.checkReadable(bad, writtenFor: "Sub/.swiftlint.yml")
        }
        #expect(error?.localizedDescription.contains("Sub/.swiftlint.yml") == true)
        #expect(throws: MirrorConfigWriteError.self) {
            try MirrorConfigWriteError.checkReadable(list, writtenFor: ".swiftlint.yml")
        }
        #expect(throws: Never.self) {
            try MirrorConfigWriteError.checkReadable(empty, writtenFor: ".swiftlint.yml")
        }
    }

    @Test("a config with exclude_ranges is written readably, with the ranges intact")
    func excludeRangesConfig() throws {
        // The engine once misaligned a list of mappings like this one, which SwiftLint can't read.
        let workspace = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try write(
            "number_separator:\n  minimum_length: 3\n  exclude_ranges:\n    - min: 1900\n      max: 2030\n",
            to: workspace.appendingPathComponent(".swiftlint.yml")
        )
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sources/A.swift"))
        let shadow = try SimulationWorkspaceBuilder()
            .makeWorkspace(for: Workspace(path: workspace), baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        let written = try text(shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(written.contains("1900"))
        #expect(written.contains("2030"))
    }
}
